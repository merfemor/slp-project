module Translator(abstractToTranslatable) where

import Syntax.Translatable as T
import Syntax.Abstract     as A
import Syntax.Error
import Data.List
import TypeChecker
import InlinedStdLibrary

type TreeTransaltor a b = a -> TranslatableProgramTree -> Either CompilationError (b, TranslatableProgramTree)

        
insertLocalVar :: [T.Function] -> Id -> Var -> (VariableId, [T.Function])
insertLocalVar fs fid v =
    let T.Function a b vs d e f = fs !! fid
        (vid,vs') = insertAndGetId vs v
    in (VariableId fid vid False, update fs (T.Function a b vs' d e f) fid)


translateMany :: (a -> c -> Either d (b, c)) -> [a] -> c -> Either d ([b], c)
translateMany _ []       s = Right ([], s)
translateMany f (x:xs) s = do
    (x', s') <- f x s 
    (xs', s'') <- translateMany f xs s'
    return $ (x' : xs', s'')


findVariable :: [T.Function] -> Id -> String -> Maybe VariableId
findVariable fs fid vn = 
    let isV = (== vn) . varName 
        f   = fs !! fid in
    case findIndex isV (T.arguments f) of
        Just vid -> Just $ VariableId fid vid True
        Nothing  -> case findIndex isV (localVars f) of
                         Just vid -> Just $ VariableId fid vid False
                         Nothing  -> do
                             ofid <- outerFunctionId f
                             findVariable fs ofid vn


findLocalFunction :: [T.Function] -> Id -> Id -> String -> Maybe Id
findLocalFunction fs iid to fn = 
    let correctOutId = \f -> outerFunctionId f == Just iid in
    case findIndex (\f -> (T.funcName f == fn) && correctOutId f) (take to fs) of
         Just ffid -> Just ffid
         Nothing   -> do
             ofid <- outerFunctionId (fs !! iid)
             findLocalFunction fs ofid to fn


findFunction :: [T.Function] -> Id -> String -> Maybe Id
findFunction fs fid fn = 
    let global = \f -> outerFunctionId f == Nothing in
    case findIndex (\f -> global f && (T.funcName f == fn)) fs of
         Just ffid -> Just ffid
         Nothing   -> findLocalFunction fs fid (length fs) fn


-- context function id -> translator
translateExpression :: Id -> TreeTransaltor A.Expression T.Expression
translateExpression _ (A.ILit a) s = Right (T.ILit a, s)
translateExpression _ (A.DLit a) s = Right (T.DLit a, s)
translateExpression _ (A.SLit sl) (sp, fp) = 
    let (sid, sp') = insertAndGetId sp sl in 
        Right (T.SLit sid, (sp', fp))

translateExpression fid (A.UnaryExpression op e) s = do
    (e', s') <- translateExpression fid e s
    return (T.UnaryExpression op e', s')

translateExpression fid (A.BinaryExpression op e1 e2) s = do
    (e1', s') <- translateExpression fid e1 s
    (e2', s'') <- translateExpression fid e2 s'
    return (T.BinaryExpression op e1' e2', s'')

translateExpression fid (A.VCall v) s@(_, fp) =
    case findVariable fp fid v of
         Nothing  -> Left $ UndefinedVariable v
         Just vid -> Right (T.VCall vid, s)

translateExpression fid (A.FCall (FunctionCall fn exs)) s@(_, fp) = 
    case findFunction fp fid fn of 
         Nothing   -> Left $ UndefinedFunction fn
         Just ffid -> do
             (exs', s') <- translateMany (translateExpression fid) exs s 
             return (T.FCall ffid exs', s')


translateBasicStatement :: Id -> TreeTransaltor A.Statement T.Statement
translateBasicStatement fid (A.FuncCall (FunctionCall n es)) s@(_,fp) = 
    case findFunction fp fid n of
         Nothing   -> Left $ UndefinedFunction n
         Just ffid -> do
             (es', s') <- translateMany (translateExpression fid) es s
             return (T.FuncCall ffid es', s')

translateBasicStatement fid (A.WhileLoop ex ss) s = do
    (ex', s') <- translateExpression fid ex s
    (ss', s'') <- translateMany (translateBasicStatement fid) ss s'
    return (T.WhileLoop ex' ss', s'')
    
translateBasicStatement fid (A.IfElse ex iss ess) s = do
    (ex', s') <- translateExpression fid ex s
    (iss', s'') <- translateMany (translateBasicStatement fid) iss s'
    (ess', s''') <- translateMany (translateBasicStatement fid) ess s''
    return (T.IfElse ex' iss' ess', s''')
    
translateBasicStatement _ (A.Return Nothing) s = Right (T.Return Nothing, s)
translateBasicStatement fid (A.Return (Just ex)) s = do
    (ex', s') <- translateExpression fid ex s
    return (T.Return (Just ex'), s')
    
translateBasicStatement fid (VarDef v ex) s = do
    (ex', (sp,fp)) <- translateExpression fid ex s
    case findVariable fp fid (varName v) of
        Nothing -> let (vid,fp') = insertLocalVar fp fid v in
                   Right (T.VarAssign vid ex', (sp,fp'))
        Just _  -> Left $ DuplicateVariableDefinition v

translateBasicStatement fid (A.VarAssign vn ex) s = do
    (ex',s'@(_,fp)) <- translateExpression fid ex s
    case findVariable fp fid vn of
         Nothing  -> Left $ UndefinedVariable vn
         Just vid -> Right (T.VarAssign vid ex', s')
         
translateBasicStatement _ _ _ = error "complex statement"


translateStatement :: Id -> TreeTransaltor A.Statement [T.Statement]
translateStatement fid (FuncDef f) s = do
    (_, s') <- translateFunction fid f s
    return ([], s')
translateStatement i st s = do
    (st', s') <- translateBasicStatement i st s
    return ([st'], s')
    

translateStatements :: Id -> TreeTransaltor [A.Statement] [T.Statement]
translateStatements fid sts s = do
    (sts', s') <- translateMany (translateStatement fid) sts s
    return (concat sts', s')


translateGlobalFunction :: TreeTransaltor A.Function ()
translateGlobalFunction (A.Function _ n _ ss) s@(_,fp) = 
    let Just fid = findIndex (\x -> T.funcName x == n) fp in do
        (ss', (sp,fp')) <- translateStatements fid ss s
        return ((), (sp, setFunctionBody fp' fid ss'))


translateFunction :: Id -> TreeTransaltor A.Function ()
translateFunction fid (A.Function t n args ss) (sp,fp) = 
    let f = T.Function t n [] args (Just fid) []
        (nfid,fp') = insertAndGetId fp f in do
    (ss', (sp',fp'')) <- translateStatements nfid ss (sp, fp')
    return ((), (sp', setFunctionBody fp'' nfid ss'))

         
makeGlobalFunctionSignatures :: TreeTransaltor AbstractProgramTree ()
makeGlobalFunctionSignatures [] s                              = Right ((), s)
makeGlobalFunctionSignatures (af@(A.Function t fn args _):fs) (sp, fp) = 
    case find (\f -> A.funcName f == fn) fs of
         Just _  -> Left $ DuplicateFunctionDefinition af
         Nothing -> let tf = T.Function t fn [] args Nothing [] in
                    makeGlobalFunctionSignatures fs (sp, fp ++ [tf])


addReturnToVoidFunc :: [T.Function] -> [T.Function]
addReturnToVoidFunc fs = map addVoid fs where
    addVoid f@(T.Function t n l a o ss)
        | t /= Nothing || ss == [] || last ss == T.Return Nothing = f
        | otherwise = T.Function Nothing n l a o (ss ++ [T.Return Nothing])
                
                
abstractToTranslatable :: AbstractProgramTree -> Either CompilationError TranslatableProgramTree
abstractToTranslatable t = do
    (_, tt) <- makeGlobalFunctionSignatures t ([], standardFunctions)
    (_, (sp,fp)) <- translateMany translateGlobalFunction t tt
    _ <- checkFunctions fp -- TODO: add return at the end of void functions
    return (sp, addReturnToVoidFunc fp)
