module Elements
    ( ring, ringNotes, ringPerc
    , tempoInterp

    , onBass, onBells, onCoil, onDrums, onVoice
    , onBassStrings
    , onBassEString, onBassAString, onBassDString, onBassGString
    )
where

import Euterpea

import Changes

-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
-- Algorithms
-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --

ring :: Dur -> [a] -> [(Dur, a)]
ring d as = zip (cycle durs) (concat $ ringOf as) ++ zip dursLast as
  where
    durs = dursFront ++ dursBack
    dursFront = map (const d) as
    dursBack = drop 1 dursFront ++ [2*d]
    dursLast = drop 1 dursFront ++ [4*d]

ringNotes :: Dur -> [a] -> Music a
ringNotes d = line . map (uncurry note) . ring d

ringPerc :: Dur -> [PercussionSound] -> Music Pitch
ringPerc d = line . map (uncurry $ flip perc) . ring d

tempoInterp :: Rational -> Rational -> Music a -> Music a
tempoInterp start end = phrase [Tmp $ Accelerando accl] . tempo start
  where
    accl = (end - start) / end

-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
-- Orchestration
-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --

onBass, onBells, onCoil, onDrums, onVoice :: Music a -> Music a
onBass  = instrument ElectricBassPicked
onBells = instrument TubularBells
onCoil  = instrument Lead2Sawtooth
onDrums = instrument Percussion
onVoice = instrument ChoirAahs

-- | To assign parts to specitic strings of the MechBass, use these.
-- They are a bit of a hack: Each is assigned a different instrument, which is
-- later mapped to the specific channel for the bass string.
onBassStrings :: [Music a -> Music a]
onBassStrings = map instrument [SlapBass1, SlapBass2, SynthBass1, SynthBass2]

onBassEString, onBassAString, onBassDString, onBassGString :: Music a -> Music a
[onBassEString, onBassAString, onBassDString, onBassGString] = onBassStrings

