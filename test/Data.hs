{-
data Bool2 where
  True : Bool2
  False : Bool2

data Bool where
  True : Bool
  False : Bool

tt : Bool2
tt = True
nil = Nil
list : boolList
list = Cons (False : Bool) (Cons (True : Bool) Nil)
boolList = List Bool

test (b : Bool) = case b of
  False -> 0
  True -> 1
  -}

data List a where
  Nil : List a
  Cons : a -> Ptr (List a) -> List a

data Maybe a where
  Nothing : Maybe a
  Just : a -> Maybe a

-- List : {a : Type 0}(A : a) -> Type (1 + max 0 (sizeof A + sizeof (Ptr (List a))))

{-
tail : forall {a}. List a -> List a
tail xs = case xs of
  Nil -> Nil
  Cons x xs' -> xs'

tail' xs = case xs of
  Nil -> Nil
  Cons x xs' -> xs'

map : forall {a b : Type _}. (a -> b) -> List a -> List b
map f xs = case xs of
  Nil -> Nil
  Cons x xs' -> Cons (f x) (map f xs')

map' f xs = case xs of
  Nil -> Nil
  Cons x xs' -> Cons (f x) (map' f xs')
  -}