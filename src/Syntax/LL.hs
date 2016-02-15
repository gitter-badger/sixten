{-# LANGUAGE DeriveFoldable, DeriveFunctor, DeriveTraversable #-}
module Syntax.LL where

import qualified Bound.Scope.Simple as Simple
import Control.Monad
import Data.Vector(Vector)
import qualified Data.Vector as Vector
import Prelude.Extras

import Syntax
import Util

data Lifted e v = Lifted (Vector (NameHint, Body Expr Tele)) (Scope Tele e v)
  deriving (Eq, Ord, Show, Functor, Foldable, Traversable)

instance Bound Lifted where
  Lifted ds d >>>= f = Lifted ds (d >>>= f)

data Body e v
  = Constant (e v)
  | Function (Vector NameHint) (Scope Tele e v)
  deriving (Eq, Ord, Show, Functor, Foldable, Traversable)

liftBody :: Hashable f => Body Expr (Var Tele f) -> (Body Expr Tele, f -> Expr b)
liftBody body = case body of
  Constant e
    | Vector.null fvs -> (Constant $ unvar err id e, pure)
    | otherwise -> (Function (mempty <$> fvs) $ 
  Function vs s -> undefined
  where
    fvs = Vector.fromList $ HashSet.toList $ toHashSet $ Simple.Scope b
    fvsLen = Vector.size fvs
    f = (`Vector.elemIndex` fvs)

instance Bound Body where
  Function vs s >>>= f = Function vs $ s >>>= f
  Constant e >>>= f = Constant $ e >>= f

type LBody = Lifted (Body Expr)

data Expr v
  = Var v
  | Global Name
  | Con Literal (Vector v) -- ^ fully applied
  | Ref (Expr v)
  | Let NameHint (Expr v) (Scope () Expr v)
  | Call v (Vector v)
  | KnownCall Name (Vector v)
  | Case v (Branches Literal Expr v)
  | Error
  deriving (Eq, Ord, Show, Functor, Foldable, Traversable)

let_' :: NameHint -> LBody v -> Simple.Scope () LBody v -> LBody v
let_' h (Lifted ds1 b1) (Scope (Lifted ds2 b2)) = case (fromScope b1, fromScope b2') of
  (Function vs f, _) -> 
  where
    (f, fScope) | Vector.null ds1 = (id, id)
                | otherwise = let fun = (+ Tele (Vector.length ds1)) in (fmap fun, mapBound f)
    ds2' = f ds2
    b2' = fScope b2

lets' :: Vector (NameHint, LBody v) -> Simple.Scope Int LBody v -> LBody v
lets' es s = unvar (error "LL.lets'") id <$> foldr go (Simple.fromScope s) (Vector.indexed es)
  where
    go :: (Int, (NameHint, LBody v)) -> LBody (Var Int v) -> LBody (Var Int v)
    go (n, (h, e)) e' = let_' h (F <$> e) $ Simple.abstract f e'
      where
        f (B n') | n == n' = Just ()
        f _ = Nothing

bind :: Expr v -> (v -> LBody v') -> LBody v'
bind expr f = case expr of
  Var v -> f v
  Global n -> undefined -- constDef $ Global n
  Con l vs -> undefined

instance Applicative Expr where
  pure = return
  (<*>) = ap

instance Monad Expr where
  return = Var
  Var v >>= f = f v
  Global g >>= _ = Global g
  Con l vs >>= f = con l $ f <$> vs
  Ref e >>= f = Ref (e >>= f)
  Let h e s >>= f = let_ h (e >>= f) (s >>>= f)
  Call v vs >>= f = call (f v) (f <$> vs)
  KnownCall g vs >>= f = call (Global g) (f <$> vs)
  Case v brs >>= f = case_ (f v) (brs >>>= f)
  Error >>= _ = Error

-------------------------------------------------------------------------------
-- Smart constructors
let_ :: NameHint -> Expr v -> Scope1 Expr v -> Expr v
let_ _ e (Scope (Var (B ()))) = e
let_ _ (Var v) s = instantiate1 (pure v) s
let_ _ (Global g) s = instantiate1 (Global g) s
let_ h e s = Let h e s

lets :: Vector (NameHint, Expr v) -> Scope Int Expr v -> Expr v
lets es s = unvar (error "LL.lets") id <$> foldr go (fromScope s) (Vector.indexed es)
  where
    go :: (Int, (NameHint, Expr v)) -> Expr (Var Int v) -> Expr (Var Int v)
    go (n, (h, e)) e' = let_ h (F <$> e) $ abstract f e'
      where
        f (B n') | n == n' = Just ()
        f _ = Nothing

call :: Expr v -> Vector (Expr v) -> Expr v
call (Global g) es
  = lets ((,) mempty <$> es)
  $ Scope $ KnownCall g $ B <$> Vector.enumFromN 0 (Vector.length es)
call e es
  = lets ((,) mempty <$> Vector.cons e es)
  $ Scope $ Call (B 0) $ B <$> Vector.enumFromN 1 (Vector.length es)

con :: Literal -> Vector (Expr v) -> Expr v
con l es
  = lets ((,) mempty <$> es)
  $ Scope $ Con l $ B <$> Vector.enumFromN 0 (Vector.length es)

case_ :: Expr v -> Branches Literal Expr v -> Expr v
case_ e brs = let_ mempty e $ Scope $ Case (B ()) $ F . pure <$> brs

-------------------------------------------------------------------------------
-- Instances
instance Eq1 Expr
instance Ord1 Expr
instance Show1 Expr