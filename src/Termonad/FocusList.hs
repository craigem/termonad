{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE TemplateHaskell #-}

module Termonad.FocusList where

import Termonad.Prelude

import Control.Lens
import Text.Show (Show(showsPrec), ShowS, showParen, showString)

data Focus = Focus Int | NoFocus deriving (Eq, Read, Show)

-- TODO: Probably be better
-- implemented as an Order statistic tree
-- (https://en.wikipedia.org/wiki/Order_statistic_tree).
data FocusList a = FocusList
  { focusListFocus :: !Focus
  , focusListLen :: {-# UNPACK #-} !Int
  , focusList :: !(IntMap a)
  }

traceShowFL :: Show a => FocusList a -> b -> b
traceShowFL fl = trace (debugFL fl)

debugFL :: Show a => FocusList a -> String
debugFL FocusList{..} =
  showString "FocusList {" .
  showString "focusListFocus = " .
  showsPrec 0 focusListFocus .
  showString ", " .
  showString "focusListLen = " .
  showsPrec 0 focusListLen .
  showString ", " .
  showString "focusList = " .
  showsPrec 0 focusList $
  showString "}" ""

instance Show a => Show (FocusList a) where
  showsPrec :: Int -> FocusList a -> ShowS
  showsPrec d FocusList{..} =
    let list = fmap fst $ sortOn fst $ mapToList focusList
    in
    showParen (d > 10) $
      showString "FocusList " .
      showsPrec 11 focusListFocus .
      showString " " .
      showsPrec 11 list

$(makeLensesFor
    [ ("focusListFocus", "lensFocusListFocus")
    , ("focusListLen", "lensFocusListLen")
    , ("focusList", "lensFocusList")
    ]
    ''FocusList
 )

foldFocus :: b -> (Int -> b) -> Focus -> b
foldFocus b _ NoFocus = b
foldFocus _ f (Focus i) = f i

lensFocusListAt :: Int -> Lens' (FocusList a) (Maybe a)
lensFocusListAt i = lensFocusList . at i

_Focus :: Prism' Focus Int
_Focus = prism' Focus (foldFocus Nothing Just)

_NoFocus :: Prism' Focus ()
_NoFocus = prism' (const NoFocus) (foldFocus (Just ()) (const Nothing))

-- | This is an invariant that the 'FocusList' must always protect.
invariantFL :: FocusList a -> Bool
invariantFL fl = False

-- | TODO: Write doctests for this function.
unsafeFLFromList :: Focus -> [a] -> FocusList a
unsafeFLFromList focus list =
  let len = length list
  in
  FocusList
    { focusListFocus = focus
    , focusListLen = len
    , focusList = mapFromList $ zip [0..] list
    }

singletonFL :: a -> FocusList a
singletonFL a =
  FocusList
    { focusListFocus = Focus 0
    , focusListLen = 1
    , focusList = singletonMap 0 a
    }

emptyFL :: FocusList a
emptyFL =
  FocusList
    { focusListFocus = NoFocus
    , focusListLen = 0
    , focusList = mempty
    }

-- | Return 'True' if the 'FocusList' is empty.
isEmptyFL :: FocusList a -> Bool
isEmptyFL fl = fl ^. lensFocusListLen == 0

-- | Append a value to the end of a 'FocusList'.
--
-- This can be thought of as a \"snoc\" operation.
appendFL :: FocusList a -> a -> FocusList a
appendFL fl a =
  if isEmptyFL fl
    then singletonFL a
    else unsafeInsertNewFL (fl ^. lensFocusListLen) a fl

-- | Prepend a value to a 'FocusList'.
--
-- This can be thought of as a \"cons\" operation.
prependFL :: a -> FocusList a -> FocusList a
prependFL a fl =
  if isEmptyFL fl
    then singletonFL a
    else unsafeInsertNewFL 0 a $ unsafeShiftUpFrom 0 fl

unsafeGetFocus :: Focus -> Int
unsafeGetFocus NoFocus = error "unsafeGetFocus: NoFocus"
unsafeGetFocus (Focus i) = i

-- | Unsafely get the value in a 'Focus' from a 'FocusList'.  If the 'Focus' is
-- 'NoFocus', this function returns 'error'.
unsafeGetFLFocus :: FocusList a -> Int
unsafeGetFLFocus fl =
  let focus = fl ^. lensFocusListFocus
  in
  case focus of
    NoFocus -> error "unsafeGetFLFocus: the focus list doesn't have a focus"
    Focus i -> i

-- | Unsafely insert a new @a@ in a 'FocusList'.  This sets the 'Int' value to
-- @a@.  The length of the 'FocusList' will be increased by 1.  The
-- 'FocusList's 'Focus' is not changed.
--
-- If there is some value in the 'FocusList' already at the 'Int', then it will
-- be overwritten.  Also, the 'Int' is not checked to make sure it is above 0.
unsafeInsertNewFL :: Int -> a -> FocusList a -> FocusList a
unsafeInsertNewFL i a fl =
  fl &
    lensFocusListLen +~ 1 &
    lensFocusListAt i ?~ a

-- | This unsafely shifts all values up in a 'FocusList'.  It also updates the
-- 'Focus' of the 'FocusList' if it has been shifted.  This does not change
-- the length of the 'FocusList'.
--
-- It does not check that the 'Int' is greater than 0.  It also does not check
-- that there is a 'Focus'.
unsafeShiftUpFrom :: forall a. Int -> FocusList a -> FocusList a
unsafeShiftUpFrom i fl =
  let intMap = fl ^. lensFocusList
      lastElemIdx = (fl ^. lensFocusListLen) - 1
      newIntMap = go i lastElemIdx intMap
      oldFocus = unsafeGetFLFocus fl
      newFocus =
        if i > lastElemIdx
          then oldFocus
          else oldFocus + 1
  in
  fl &
    lensFocusList .~ newIntMap &
    lensFocusListFocus .~ Focus newFocus
  where
    go :: Int -> Int -> IntMap a -> IntMap a
    go idxToInsert idxToShiftUp intMap
      | idxToInsert <= idxToShiftUp =
        let val = unsafeLookup idxToShiftUp intMap
            newMap =
              insertMap (idxToShiftUp + 1) val (deleteMap idxToShiftUp intMap)
        in go idxToInsert (idxToShiftUp - 1) newMap
      | otherwise = intMap

-- | This is an unsafe lookup function.  This assumes that the 'Int' exists in
-- the 'IntMap'.
unsafeLookup :: Int -> IntMap a -> a
unsafeLookup i intmap =
  case lookup i intmap of
    Nothing -> error $ "unsafeLookup: key " <> show i <> " not found in intmap"
    Just a -> a

-- | Insert a new value into the 'FocusList'.  The 'Focus' of the list is
-- changed appropriately.
--
-- This returns 'Nothing' if the index at which to insert the new value is
-- either less than 0 or greater than the length of the list.
insertFL
  :: Int  -- ^ The index at which to insert the value.
  -> a
  -> FocusList a
  -> Maybe (FocusList a)
insertFL i a fl =
  if i < 0 || i > (fl ^. lensFocusListLen)
    then
      -- Return Nothing if the insertion position is out of bounds.
      Nothing
    else
      -- Otherwise, shift all existing values up one and insert the new
      -- value in the opened place.
      let shiftedUpFL = unsafeShiftUpFrom i fl
      in Just $ unsafeInsertNewFL i a shiftedUpFL

-- | Unsafely remove a value from a 'FocusList'.  It effectively leaves a hole
-- inside the 'FocusList'.
--
-- This function does not check that a value actually exists in the
-- 'FocusList'.  It also does not update the 'Focus'.
--
-- This function does update the length of the 'FocusList'.
unsafeRemove
  :: Int
  -> FocusList a
  -> FocusList a
unsafeRemove i fl =
  fl &
    lensFocusListLen -~ 1 &
    lensFocusListAt i .~ Nothing

-- | TODO: Write doctests for this function.
unsafeShiftDownFrom :: forall a. Int -> FocusList a -> FocusList a
unsafeShiftDownFrom i fl =
  let intMap = fl ^. lensFocusList
      len = fl ^. lensFocusListLen
      newIntMap = go (i + 1) len intMap
  in fl & lensFocusList .~ newIntMap
  where
    go :: Int -> Int -> IntMap a -> IntMap a
    go idxToShiftDown len intMap
      | idxToShiftDown < len =
        let val = unsafeLookup idxToShiftDown intMap
            newMap =
              insertMap (idxToShiftDown - 1) val (deleteMap idxToShiftDown intMap)
        in go (idxToShiftDown + 1) len newMap
      | otherwise = intMap

-- | Remove an element from a 'FocusList'.
--
-- TODO: Finish writing doctests for this function.
--
-- If the element to remove is not the 'Focus', then update the 'Focus'
-- accordingly.  (For example, if the 'Focus' is on index 1, and we have
-- removed index 3, then the focus is not affected, so it is not changed.  If
-- the 'Focus' is on index 3 and we have removed index 1, then the 'Focus' will
-- be set to 2.)
--
-- >>> let focusList = unsafeFLFromList (Focus 1) [0,1,2,3,4]
-- >>> removeFL 3 focusList
-- Just (FocusList (Focus 1) [0,1,2,4])
--
-- >>> let focusList = unsafeFLFromList (Focus 3) [0,1,2,3,4]
-- >>> removeFL 1 focusList
-- Just (FocusList (Focus 2) [0,2,3,4])
--
-- If the element to remove is the only element in the list, then the 'Focus'
-- will be set to 'NoFocus'.
--
-- >>> let focusList = unsafeFLFromList (Focus 0) ["hello"]
-- >>> removeFL 0 focusList
-- Just (FocusList NoFocus [])
--
-- If the element to remove is the 'Focus', then use the value passed in as
-- new 'Focus'.  This lets the use decide which element should get
-- the new focus.  Keep in mind that if the old 'Focus' was index 8, and the
-- function returns the new 'Focus' as index 8, then effectively the element
-- AFTER the element that was removed will have the focus.
--
-- If the 'Int' for the index to remove is either less than 0 or greater then
-- the length of the list, then 'Nothing' is returned.  If the 'FocusList'
-- passed in is 'Empty', then 'Nothing' is returned.  If the 'Int' returned
-- by the update function is less than 0 or greater than the length of the new
-- list, then 'Nothing' is returned.
removeFL
  :: Show a => Int          -- ^ Index of the element to remove from the 'FocusList'.
  -> FocusList a  -- ^ The 'FocusList' to remove an element from.
  -> Maybe (FocusList a)
removeFL i fl
  | i < 0 || i >= (fl ^. lensFocusListLen) || isEmptyFL fl =
    -- Return Nothing if the removal position is out of bounds.
    Nothing
  | fl ^. lensFocusListLen == 1 =
    -- Return an empty focus list if there is currently only one element
    Just emptyFL
  | otherwise =
    let newFLWithHole = unsafeRemove i fl
        newFL = unsafeShiftDownFrom i newFLWithHole
    in
    if traceShowFL newFLWithHole $ i == newFL ^. lensFocusListLen
      then
        -- The last item was deleted, so set the current last item as the
        -- focus.
        Just $ newFL & lensFocusListFocus . _Focus -~ 1
      else
        -- The new focus will be item AFTER the old @i@, which should have
        -- the same index as @i@ now.
        Just newFL