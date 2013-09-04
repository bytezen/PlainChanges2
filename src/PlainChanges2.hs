module PlainChanges2 where

import Codec.Midi
import Data.List (isPrefixOf)
import Euterpea
import Euterpea.IO.MIDI.MidiIO (getAllDevices)

import qualified Coil
import qualified MechBass
import qualified MechBassAllocator as MechBass
import MidiUtil
import PartI
import PartII
import PartIII
import Tests

import Sound.MidiPlayer

plainChanges2_30 :: Music Pitch
plainChanges2_30 =
    rest wn
    :+: preamble
    :+: rest (2*wn)
    :+: partI
    :+: rest (2*wn)
    :+: partII
    :+: rest (2*wn)
    :+: partIII

-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
-- Performance
-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --

-- | Maps parts, identified by instruments, to MIDI channels
-- The bass part, as composed, is either on the strings indvidually, or on the
-- whole bass part channel.
patchMap :: UserPatchMap   -- N.B.: 0-based midi channels!
patchMap = [ (SynthBass2, 0)            -- MechBass G string
           , (SynthBass1, 1)            -- MechBass D string
           , (SlapBass2, 2)             -- MechBass A string
           , (SlapBass1, 3)             -- MechBass E string
           , (ElectricBassPicked, 4)    -- whole bass part
           , (Lead2Sawtooth, 5)         -- Coil
           , (TubularBells, 6)          -- bells
           , (ChoirAahs, 7)             -- voices
           , (Percussion, 9)            -- drums
           ]

-- | Convert music to MIDI, as composed. Generally this form isn't playable
-- directly, as the bass part is divided amongst five channels.
composedMidi :: Music Pitch -> Midi
composedMidi m = toMidi (defToPerf m) patchMap

-- | Convert music to MIDI for performance. This has all the bass parts prepared
-- for the MechBass, with string allocations and pre-positioning events.
performanceMidi :: Music Pitch -> Midi
performanceMidi = preparePerformance . composedMidi

-- | Prepare MIDI for performance. Full bass part is allocated to strings, and
-- all bass parts are adjusted with pre-positioning events.
preparePerformance :: Midi -> Midi
preparePerformance = snd . allocateBass . snd . restrictCoil

-- | Prepare MIDI for preview on synths. Bass parts are combined back into a
-- single track, and any pre-positioning evnets are removed.
preparePreview :: Midi -> Midi
preparePreview = processTracks (MechBass.recombine 4)


-- | Play music as composed, on synthesizers
playOnSynth :: Music Pitch -> IO ()
playOnSynth = midiOnSynth . composedMidi

-- | Play music as performed, on synthesizers
performOnSynth :: Music Pitch -> IO ()
performOnSynth = midiOnSynth . preparePerformance . composedMidi

-- | Play MIDI on synthesizers. The MIDI is prepared for preview (bass on one
-- channel). Plays on the first output port of the IAC Driver.
midiOnSynth :: Midi -> IO ()
midiOnSynth midi = do
    devs <- getAllDevices
    case findIacOutput devs of
        ((iacOut,_):_) -> midiPlayer iacOut $ preparePreview midi
        [] -> putStrLn "*** No IAC Driver output found"
  where
    findIacOutput = filter (namedIAC . snd) .  filter (output . snd)
    namedIAC = ("IAC Driver" `isPrefixOf`) . name


restrictCoil :: Midi -> (Coil.Messages, Midi)
restrictCoil = processChannels Coil.restrict (== 5)

allocateBass :: Midi -> (MechBass.AllocMessages, Midi)
allocateBass = processChannels MechBass.allocator (<= 4)

validateCoil :: Midi -> [String]
validateCoil m = "== Coil Validation ==" :
    runCheckChannel 5 Coil.validate m

validateBass :: Midi -> [String]
validateBass m = "== Bass Validation ==" :
    concat (zipWith run MechBass.bassChannels MechBass.bassStrings)
  where
    run ch bs = ("-- Channel " ++ show ch ++ " --") :
        runCheckChannel ch (MechBass.validate bs) m

prepareMidiFiles :: String -> Music Pitch -> IO ()
prepareMidiFiles prefix m = do
    writeMidiFile (prefix ++ "-composed") mComposed
    writeMidiFile (prefix ++ "-performed") mPerformed
    writeMidiFile (prefix ++ "-dropped") mDropped
    writeMidiFile (prefix ++ "-previewed") mPreviewed
    writeFile (prefix ++ "-log.txt") $ unlines logLines
  where
    mComposed = composedMidi $ rest hn :+: m
    (cMsgs, mRestricted) = restrictCoil mComposed
    (bMsgs, mAllocated) = allocateBass mRestricted
    mPreviewed = preparePreview mAllocated
    mPerformed = filterMessages (not . isProgramChange) mAllocated
    mDropped = processTracks (Coil.dropAnOctave 5) mPerformed

    logLines = validateCoil mPerformed
            ++ validateBass mPerformed
            ++ "== Coil Restriction ==" : showErrorMessages cMsgs
            ++ "== Bass Allocation ==" : showErrorMessages bMsgs

writeMidiFile :: String -> Midi -> IO ()
writeMidiFile path midi = do
    exportFile (path ++ ".midi") midi'
    writeFile (path ++ ".txt") $ unlines $ dumpMidi midi'
  where
    midi' = prepTrackEnds midi


debugAllParts :: IO ()
debugAllParts = do
    prepareMidiFiles "dump/plain-changes-2" plainChanges2_30
    prepareMidiFiles "dump/preamble" preamble
    prepareMidiFiles "dump/partI" partI
    prepareMidiFiles "dump/partII" partII
    prepareMidiFiles "dump/partIII" partIII
    prepareMidiFiles "dump/level-test" levelTest
    prepareMidiFiles "dump/bass-volume-test" bassVolumeTest
    prepareMidiFiles "dump/bass-timing-test" bassTimingTest

