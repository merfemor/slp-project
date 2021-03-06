module Syntax.Translatable where

import Syntax.Abstract ( UnaryOperation
                       , BinaryOperation
                       , VoidableType
                       , Var(..)
                       )
import Data.List()

type Id = Int

data VariableId = VariableId { funcId :: Id
                             , varId :: Id
                             , isArgument :: Bool
                             } deriving (Eq, Show)

data Function = Function { returnType :: VoidableType
                         , funcName :: String
                         , localVars :: [Var]
                         , arguments :: [Var]
                         , outerFunctionId :: Maybe Id
                         , functionBody :: [Statement]
                         } deriving Show

instance Eq Function where
    f == g = funcName f == funcName g && outerFunctionId f == outerFunctionId g
                         
                         
data Expression = SLit Id
                | ILit Int
                | DLit Double
                | UnaryExpression UnaryOperation Expression
                | BinaryExpression BinaryOperation Expression Expression
                | FCall Id [Expression]
                | VCall VariableId
                deriving (Eq, Show)
                
data Statement = VarAssign VariableId  Expression
               | WhileLoop Expression [Statement]
               | IfElse Expression [Statement] [Statement]
               | Return (Maybe Expression)
               | FuncCall Id [Expression] deriving (Eq, Show)

-- string pool and function list
type TranslatableProgramTree = ([String], [Function])


insertAndGetId :: [a] -> a -> (Int, [a])
insertAndGetId l e = (length l, l ++ [e])


update :: [a] -> a -> Int -> [a]
update xs e i = take i xs ++ [e] ++ drop (i + 1) xs


subList :: [a] -> Int -> Int -> [a]
subList l f t = drop f . take t $ l


setFunctionBody :: [Function] -> Id -> [Statement] -> [Function]
setFunctionBody fs fid ss = 
    let Function a b c d e _ = fs !! fid in
        update fs (Function a b c d e ss) fid
        
{-        
eitherStateChain :: (a -> d -> Either b c) -> [a] -> d -> Either b [c]
eitherStateChain _ []     _   = Right []
eitherStateChain f (x:xs) fns = do
    x <- f x fns 
    xs <- eitherStateChain f xs fns
    return (x:xs)
    -} 
-- TODO: does this function need somewhere?
