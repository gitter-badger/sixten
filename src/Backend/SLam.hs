{-# LANGUAGE MonadComprehensions, OverloadedStrings, ViewPatterns #-}
module Backend.SLam where

import Bound.Scope hiding (instantiate1)
import Control.Monad.Except
import Data.Monoid
import qualified Data.Vector as Vector

import qualified Builtin
import Syntax
import qualified Syntax.Abstract as Abstract
import qualified Syntax.Sized.SLambda as SLambda
import Meta
import Inference.TypeOf
import TCM

slamS :: AbstractM -> TCM LambdaM
slamS e = SLambda.Anno <$> slam e <*> (slam =<< typeOf e)

slam :: AbstractM -> TCM LambdaM
slam expr = do
  logMeta 20 "slam expr" expr
  modifyIndent succ
  res <- case expr of
    Abstract.Var v -> return $ SLambda.Var v
    Abstract.Global g -> return $ SLambda.Global g
    Abstract.Lit l -> return $ SLambda.Lit l
    Abstract.Pi {} -> return $ SLambda.Global Builtin.PiTypeName
    Abstract.Lam h p t s -> do
      v <- forall h p t
      e <- slamS $ instantiate1 (pure v) s
      sz <- slam t
      return $ SLambda.Lam h sz $ abstract1 v e
    (appsView -> (Abstract.Con qc, es)) -> do
      n <- constrArity qc
      case compare argsLen n of
        GT -> throwError $ "slam: too many args for constructor: " ++ show qc
        EQ -> SLambda.Con qc <$> mapM slamS (Vector.fromList $ snd <$> es)
        LT -> do
          conType <- qconstructor qc
          let Just appliedConType = typeApps conType $ snd <$> es
              tele = telescope appliedConType
          slam $ lams tele
                $ Scope
                $ apps (Abstract.Con qc)
                $ Vector.fromList (fmap (pure . pure) <$> es)
                <> iforTele tele (\i _ a _ -> (a, pure $ B $ Tele i))
      where
        argsLen = length es
    Abstract.Con _qc -> throwError "slam impossible"
    Abstract.App e1 _ e2 -> SLambda.App <$> slam e1 <*> slamS e2
    Abstract.Case e brs -> SLambda.Case <$> slamS e <*> slamBrances brs
    Abstract.Let h e scope -> do
      t <- typeOf e
      v <- forall h Explicit t
      e' <- slamS e
      sz <- slam t
      body <- slamS $ instantiate1 (pure v) scope
      return $ SLambda.Let h e' sz $ abstract1 v body
  modifyIndent pred
  logMeta 20 "slam res" res
  return res

slamBrances
  :: Pretty c
  => Branches c Plicitness Abstract.Expr MetaA
  -> TCM (Branches c () SLambda.Expr MetaA)
slamBrances (ConBranches cbrs) = do
  logMeta 20 "slamBrances brs" $ ConBranches cbrs
  modifyIndent succ
  cbrs' <- forM cbrs $ \(c, tele, brScope) -> do
    tele' <- forTeleWithPrefixM tele $ \h a s tele' -> do
      let vs = fst <$> tele'
          abstr = teleAbstraction vs
          t = instantiateTele pure vs s
      tsz <- slam t
      v <- forall h a t
      return (v, (h, a, abstract abstr tsz))
    let vs = fst <$> tele'
        abstr = teleAbstraction vs
        tele'' = Telescope
               $ fmap (\(h, _, t) -> (h, (), t))
               $ snd <$> tele'
    brScope' <- slam $ instantiateTele pure vs brScope
    return (c, tele'', abstract abstr brScope')
  modifyIndent pred
  logMeta 20 "slamBrances res" $ ConBranches cbrs'
  return $ ConBranches cbrs'
slamBrances (LitBranches lbrs d)
  = LitBranches
    <$> sequence [(,) l <$> slam e | (l, e) <- lbrs]
    <*> slam d
slamBrances (NoBranches typ) = NoBranches <$> slam typ

slamDef
  :: Definition Abstract.Expr MetaA
  -> TCM LambdaM
slamDef (Definition e) = slamS e
slamDef (DataDefinition _ e) = slamS e
