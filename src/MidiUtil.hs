module MidiUtil
    ( Checker, CheckResult
    , check, okay

    , extractChannel

    , TrackChecker
    , checkChannel, runCheckChannel
    , processChannel
    , processTracks

    , showErrorMessages
    , dumpMidi

    , messageOrder
    )
where

import Codec.Midi as M
import Control.Monad.Trans.Writer (Writer, execWriter, tell)
import Data.Bits ((.|.), (.&.), shiftL, shiftR)
import Data.List (foldl', partition)
import Text.Printf (printf)


type Checker err = Writer [(M.Time, err)] ()
type CheckResult err = Either [(M.Time, err)] ()

execChecker :: Checker err -> CheckResult err
execChecker c = case execWriter c of
    [] -> Right ()
    errs -> Left errs

check :: M.Time -> Bool -> err -> Checker err
check _ True _ = return ()
check t False err = tell [(t, err)]

okay :: Checker a
okay = return ()


-- | Extract eveything for a single channel from a group of tracks into a single
-- track, and a collections of tracks of the remainder. Tracks which don't
-- contain the channel at all are included verbatim in the remainder. Tracks
-- which contain only the channel, are merged fully into the single track.
-- Tracks which mix the channel with others, are divided, with events for the
-- channel merged into the other channel's tracks, and the rest included in the
-- remainder.
partitionChannel :: (Num a, Ord a) => M.Channel -> [M.Track a] -> (M.Track a, [M.Track a])
partitionChannel ch trks = (chTrk, noChTrks)
  where
    (trks', noChTrks1) = partition (trackHasChannel ch) trks
    (mixedTracks, chTrks1) = partition (trackHasOtherChannel ch) trks'
    (chTrks2, noChTrks2) = unzip $ map splitter mixedTracks
    chTrk = foldl' M.merge [] $ chTrks1 ++ chTrks2
    noChTrks = noChTrks1 ++ noChTrks2
    splitter = fromAbsTime2 . partition (messageOnChannel ch . snd) . toAbsTime
    fromAbsTime2 (a, b) = (fromAbsTime a, fromAbsTime b)

-- | Does a track have events on a given channel.
trackHasChannel :: M.Channel -> M.Track a -> Bool
trackHasChannel ch = not . null . filter (messageOnChannel ch . snd)

-- | Does a track have events on a channel other than the given channel.
-- Note: This is not the opposite of `trackHasChannel`: Tracks may have events
-- on multiple channels, or no channels at all.
trackHasOtherChannel :: M.Channel -> M.Track a -> Bool
trackHasOtherChannel ch =
    not . null . filter (maybe False (/= ch) . messageChannel . snd)

-- | Is event on a given channel?
messageOnChannel :: M.Channel -> M.Message -> Bool
messageOnChannel ch = (== Just ch) . messageChannel

-- | Return the channel of an event, if any.
messageChannel :: M.Message -> Maybe M.Channel
messageChannel m = if M.isChannelMessage m then Just (M.channel m) else Nothing


prop_partitionGetsAll :: [M.Track M.Ticks] -> Bool
prop_partitionGetsAll =
    not . trackHasChannel 0 . concat . snd . partitionChannel 0

prop_partitionHasOnly :: [M.Track M.Ticks] -> Bool
prop_partitionHasOnly =
    not . trackHasOtherChannel 0 . fst . partitionChannel 0

extractChannel :: M.Channel -> M.Midi -> M.Track M.Ticks
extractChannel ch = fst . partitionChannel ch . tracks



type TrackChecker err = M.Track M.Time -> Checker err

checkChannel :: M.Channel -> TrackChecker err -> M.Midi -> CheckResult err
checkChannel ch chkr midi = execChecker $ chkr $ convert chTrack
  where
    chTrack = fst $ partitionChannel ch $ tracks midi
    convert = toRealTime (timeDiv midi) . toAbsTime

runCheckChannel :: (Show err) => M.Channel -> TrackChecker err -> M.Midi -> [String]
runCheckChannel ch chkr midi = case checkChannel ch chkr midi of
    Left errs -> showErrorMessages errs
    Right () -> ["PASSED"]

showErrorMessages :: (Show err) => [(Time, err)] -> [String]
showErrorMessages = map (\(t,e) -> printf "%8.3f %s" t $ show e)


processChannel :: (M.Track Time -> (a, M.Track Time)) -> M.Channel -> M.Midi -> (a, M.Midi)
processChannel f ch midi = (a, midi')
  where
    (chTrack, otherTracks) = partitionChannel ch $ tracks midi
    (a, chTrack') = f . toRealTime td . toAbsTime $ chTrack
    chTrack'' = fromAbsTime . fromRealTime td $ chTrack'
    midi' = midi { fileType = ft, tracks = chTrack'' : otherTracks }
    ft = if null otherTracks then SingleTrack else MultiTrack
    td = timeDiv midi

processTracks :: (M.Track Time -> M.Track Time) -> M.Midi -> M.Midi
processTracks f midi = midi { tracks = map (t' . f . t) $ tracks midi }
  where
    t = toRealTime td . toAbsTime
    t' = fromAbsTime . fromRealTime td
    td = timeDiv midi

dumpMidi :: M.Midi -> [String]
dumpMidi midi = show (fileType midi) : show (timeDiv midi) : showTracks
  where
    showTracks = concat $ zipWith showTrack [(0::Int)..] $ tracks midi
    showTrack n tr =
        (printf "==Track %2d" n ++ concatMap (printf ":ch%2d") [0..15::Int])
        : map showEvent (toRealTime (timeDiv midi) $ toAbsTime tr)
    showEvent (te, ev) = printf "%10.3f " te ++ case ev of
        NoteOff ch k v          -> indent ch ++ "-" ++ key k ++ val v
        NoteOn ch k v  | v >  1 -> indent ch ++ "⬥" ++ key k ++ val v
                    | otherwise -> indent ch ++ "⬦" ++ key k ++ val v
        KeyPressure ch k v      -> indent ch ++ "⬎" ++ key k ++ val v
        ControlChange ch n v    -> indent ch ++ "cc" ++ val n ++ val v
        ProgramChange ch n      -> indent ch ++ "#" ++ val n
        ChannelPressure ch p    -> indent ch ++ "⬎⬎" ++ val p
        PitchWheel ch p         -> indent ch ++ "⦵ " ++ show p
        _ -> show ev
    indent ch = replicate (5*ch) ' '
    key = printf " %2d"
    val = printf " %3d"



messageOrder :: M.Message -> Int
messageOrder m = case m of
    NoteOff c k v         -> channelOrder 0x80 c k v
    NoteOn c k v          -> channelOrder 0x90 c k v
    KeyPressure  c k p    -> channelOrder 0xA0 c k p
    ControlChange c n v   -> channelOrder 0xB0 c n v
    ProgramChange c p     -> channelOrder 0x40 c p 0
    ChannelPressure c p   -> channelOrder 0xD0 c p 0
    PitchWheel c p        -> channelOrder 0xE0 c (p `shiftR` 8) (p .&. 255)
    SequenceNumber _      -> metaOrder 0 0x00
    Text _                -> metaOrder 3 0x01
    Copyright _           -> metaOrder 3 0x02
    TrackName _           -> metaOrder 3 0x03
    InstrumentName _      -> metaOrder 3 0x04
    Lyrics _              -> metaOrder 3 0x05
    Marker _              -> metaOrder 2 0x06
    CuePoint _            -> metaOrder 2 0x07
    ChannelPrefix _       -> metaOrder 1 0x20
    ProgramName _         -> metaOrder 3 0x08
    DeviceName _          -> metaOrder 3 0x09
    TrackEnd              -> metaOrder 9 0x2F
    TempoChange _         -> metaOrder 2 0x51
    SMPTEOffset _ _ _ _ _ -> metaOrder 2 0x54
    TimeSignature _ _ _ _ -> metaOrder 2 0x58
    KeySignature _ _      -> metaOrder 3 0x59
    Reserved w _          -> metaOrder 4 w
    Sysex s _             -> metaOrder 4 s
  where
    channelOrder t c a b = order4 5 (t .|. c) a b
    metaOrder n x = order4 n x 0 0
    order4 w x y z =
        (w `shiftL` 24) .|. (x `shiftL` 16) .|. (y `shiftL` 8) .|. z
