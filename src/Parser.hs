{-# LANGUAGE FlexibleContexts #-}

module Parser where

import Syntax
import Text.ParserCombinators.Parsec
import Text.Parsec.Expr
import Text.ParserCombinators.Parsec.Language
import Data.Char(isSpace)
import qualified Data.Map as Map
import qualified Text.ParserCombinators.Parsec.Token as Token


-- get key by value in Map
lookupR :: Eq b => b -> Map.Map c b -> c
lookupR v = fst . head . Map.assocs . (Map.filter (==v))


lexer         = Token.makeTokenParser languageDef

identifier    = Token.identifier    lexer -- parses an identifier
reserved      = Token.reserved      lexer -- parses a reserved name
reservedOp    = Token.reservedOp    lexer -- parses an operator
parens        = Token.parens        lexer -- parses surrounding parenthesis:
braces        = Token.braces        lexer
commaSep      = Token.commaSep      lexer
float         = Token.float         lexer -- parses a floating point value
stringLiteral = Token.stringLiteral lexer --parses a literal string


int :: Parser Int
int = fromIntegral <$> (Token.integer lexer)


double :: Parser Double
double = try float <|> fromIntegral <$> int

{-
-- skips tabs and spaces
tabsSpaces :: Parser ()
tabsSpaces = skipMany $ oneOf "\t "


varDefine :: Parser String
varDefine = do
   spaces
   id <- identifier
   spaces
   char '='
   spaces
   return id


oneOfKeys :: Map.Map String a -> Parser a
oneOfKeys m = ((Map.!) m) <$> (choice . map string . Map.keys $ m)
-}

sepExpressions :: Parser [Expression]
sepExpressions = commaSep expressionParser


functionCall :: Parser FunctionCall
functionCall = do
    f <- identifier
    a <- parens sepExpressions
    return $ FunctionCall f a


unOp op = Prefix $ do
    spaces
    string (lookupR op unaryOperations)
    spaces
    return $ UnaryExpression op


binOp op = Infix (do
    spaces
    string (lookupR op binaryOperations)
    spaces
    return $ BinaryExpression op) AssocLeft


operations = [[unOp Not, unOp Neg],
              [binOp Mul, binOp Div],
              [binOp Sum, binOp Sub],
              [binOp L, binOp G, binOp GE, binOp LE],
              [binOp Eq, binOp NotE],
              [binOp And],
              [binOp Or]]


subExpression :: Parser Expression
subExpression = parens expressionParser
            <|> try (FCall  <$> functionCall)
            <|> VCall  <$> identifier
            <|> NumVar <$> double
            <|> SVar   <$> stringLiteral


expressionParser :: Parser Expression
expressionParser = buildExpressionParser operations subExpression