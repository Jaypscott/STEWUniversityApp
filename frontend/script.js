const API_URL = "https://stew-university-backend.onrender.com";

const noteOrder = [
    "C", "C#", "D", "D#", "E", "F",
    "F#", "G", "G#", "A", "A#", "B"
];

const whiteNotes = ["C", "D", "E", "F", "G", "A", "B"];

const guitarStrings = ["E", "B", "G", "D", "A", "E"];
const bassStrings = ["G", "D", "A", "E"];
const noteFrequencies = {
    "C": 261.63,
    "C#": 277.18,
    "D": 293.66,
    "D#": 311.13,
    "E": 329.63,
    "F": 349.23,
    "F#": 369.99,
    "G": 392.00,
    "G#": 415.30,
    "A": 440.00,
    "A#": 466.16,
    "B": 493.88
};

const pianoSampleBasePath = "assets/piano/package/audio";
const pianoSampleFiles = [
    "A0v8.ogg", "A1v8.ogg", "A2v8.ogg", "A3v8.ogg",
    "A4v8.ogg", "A5v8.ogg", "A6v8.ogg", "A7v8.ogg",
    "C1v8.ogg", "C2v8.ogg", "C3v8.ogg", "C4v8.ogg",
    "C5v8.ogg", "C6v8.ogg", "C7v8.ogg", "C8v8.ogg",
    "D#1v8.ogg", "D#2v8.ogg", "D#3v8.ogg", "D#4v8.ogg",
    "D#5v8.ogg", "D#6v8.ogg", "D#7v8.ogg",
    "F#1v8.ogg", "F#2v8.ogg", "F#3v8.ogg", "F#4v8.ogg",
    "F#5v8.ogg", "F#6v8.ogg", "F#7v8.ogg"
];

const guitarSampleBasePath = "assets/guitar/package";
const guitarSampleFiles = [
    "A2.ogg", "A3.ogg", "A4.ogg",
    "As2.ogg", "As3.ogg", "As4.ogg",
    "B2.ogg", "B3.ogg", "B4.ogg",
    "C3.ogg", "C4.ogg", "C5.ogg",
    "Cs3.ogg", "Cs4.ogg", "Cs5.ogg",
    "D2.ogg", "D3.ogg", "D4.ogg", "D5.ogg",
    "Ds2.ogg", "Ds3.ogg", "Ds4.ogg",
    "E2.ogg", "E3.ogg", "E4.ogg",
    "F2.ogg", "F3.ogg", "F4.ogg",
    "Fs2.ogg", "Fs3.ogg", "Fs4.ogg",
    "G2.ogg", "G3.ogg", "G4.ogg",
    "Gs2.ogg", "Gs3.ogg", "Gs4.ogg"
];

const bassSampleBasePath = "assets/bass/package";
const bassSampleFiles = [
    "As1.ogg", "As2.ogg", "As3.ogg", "As4.ogg",
    "Cs1.ogg", "Cs2.ogg", "Cs3.ogg", "Cs4.ogg", "Cs5.ogg",
    "E1.ogg", "E2.ogg", "E3.ogg", "E4.ogg",
    "G1.ogg", "G2.ogg", "G3.ogg", "G4.ogg"
];

const noteToSemitone = {
    "C": 0,
    "C#": 1,
    "D": 2,
    "D#": 3,
    "E": 4,
    "F": 5,
    "F#": 6,
    "G": 7,
    "G#": 8,
    "A": 9,
    "A#": 10,
    "B": 11
};

const flatToSharpMap = {
    "Bb": "A#",
    "Db": "C#",
    "Eb": "D#",
    "Gb": "F#",
    "Ab": "G#"
};

function getSampleNoteFromFileName(fileName) {
    return fileName
        .replace("v8.ogg", "")
        .replace(".ogg", "")
        .replace("As", "A#")
        .replace("Cs", "C#")
        .replace("Ds", "D#")
        .replace("Fs", "F#")
        .replace("Gs", "G#");
}

function buildInstrumentSamples(fileNames) {
    return fileNames.map(fileName => {
        const sampleNote = getSampleNoteFromFileName(fileName);
        const match = sampleNote.match(/^([A-G]#?)(\d)$/);
        const note = match[1];
        const octave = Number(match[2]);

        return {
            fileName,
            midi: getMidiNote(note, octave)
        };
    });
}

const instrumentSamples = {
    piano: {
        basePath: pianoSampleBasePath,
        samples: buildInstrumentSamples(pianoSampleFiles),
        cache: {},
        gain: 0.42
    },
    guitar: {
        basePath: guitarSampleBasePath,
        samples: buildInstrumentSamples(guitarSampleFiles),
        cache: {},
        gain: 0.44
    },
    bass: {
        basePath: bassSampleBasePath,
        samples: buildInstrumentSamples(bassSampleFiles),
        cache: {},
        gain: 0.5
    }
};

const visualizerDefaultOctaves = {
    piano: 4,
    guitar: 3,
    bass: 2
};

const openStringMidis = {
    guitar: [64, 59, 55, 50, 45, 40],
    bass: [43, 38, 33, 28]
};

const fretboardConfigs = {
    guitar: {
        strings: guitarStrings,
        openMidis: openStringMidis.guitar,
        frets: 12,
        maxSpan: 4,
        label: "Guitar"
    },
    bass: {
        strings: bassStrings,
        openMidis: openStringMidis.bass,
        frets: 12,
        maxSpan: 5,
        label: "Bass"
    }
};

const guitarShapeAnchors = {
    shape1: 5,
    shape2: 4,
    shape3: 3
};

const pianoSamples = pianoSampleFiles.map(fileName => {
    const sampleNote = getSampleNoteFromFileName(fileName);
    const match = sampleNote.match(/^([A-G]#?)(\d)$/);
    const note = match[1];
    const octave = Number(match[2]);

    return {
        fileName,
        midi: getMidiNote(note, octave)
    };
});

const pianoSampleCache = {};

const displayNoteMap = {
    "C": "C",
    "C#": "C#/Db",
    "D": "D",
    "D#": "D#/Eb",
    "E": "E",
    "F": "F",
    "F#": "F#/Gb",
    "G": "G",
    "G#": "G#/Ab",
    "A": "A",
    "A#": "A#/Bb",
    "B": "B"
};

function getDisplayNote(note) {
    return displayNoteMap[note] || note;
}

const enharmonicMap = {
    "Bb": "A#",
    "Db": "C#",
    "Eb": "D#",
    "Gb": "F#",
    "Ab": "G#",
    "Cb": "B",
    "Fb": "E",
    "E#": "F",
    "B#": "C"
};

let audioContext = null;

function getAudioContext() {
    if (!audioContext) {
        audioContext = new (window.AudioContext || window.webkitAudioContext)();
    }

    if (audioContext.state === "suspended") {
        audioContext.resume();
    }

    return audioContext;
}

function getSafeAudioStartTime(audioContext, requestedStartTime) {
    return Math.max(requestedStartTime, audioContext.currentTime + 0.03);
}

function getMidiNote(note, octave) {
    return (octave + 1) * 12 + noteToSemitone[note];
}

function midiToFrequency(midi) {
    return 440 * Math.pow(2, (midi - 69) / 12);
}

function getNoteMidi(noteWithOptionalOctave, defaultOctave = 4) {
    const match = noteWithOptionalOctave.match(/^([A-G](?:#|b)?)(\d)?$/);

    if (!match) {
        return null;
    }

    const note = flatToSharpMap[match[1]] || match[1];
    const octave = match[2] ? Number(match[2]) : defaultOctave;

    if (noteToSemitone[note] === undefined) {
        return null;
    }

    return getMidiNote(note, octave);
}

function getNearestPianoSample(midi) {
    return pianoSamples.reduce((nearest, sample) => {
        const nearestDistance = Math.abs(nearest.midi - midi);
        const sampleDistance = Math.abs(sample.midi - midi);
        return sampleDistance < nearestDistance ? sample : nearest;
    });
}

function getNearestInstrumentSample(instrument, midi) {
    const config = instrumentSamples[instrument] || instrumentSamples.piano;

    return config.samples.reduce((nearest, sample) => {
        const nearestDistance = Math.abs(nearest.midi - midi);
        const sampleDistance = Math.abs(sample.midi - midi);
        return sampleDistance < nearestDistance ? sample : nearest;
    });
}

async function loadPianoSample(sample) {
    if (pianoSampleCache[sample.fileName]) {
        return pianoSampleCache[sample.fileName];
    }

    const audioContext = getAudioContext();
    const sampleUrl = `${pianoSampleBasePath}/${encodeURIComponent(sample.fileName)}`;
    const response = await fetch(sampleUrl);

    if (!response.ok) {
        throw new Error(`Could not load piano sample: ${sample.fileName}`);
    }

    const arrayBuffer = await response.arrayBuffer();
    const audioBuffer = await audioContext.decodeAudioData(arrayBuffer);
    pianoSampleCache[sample.fileName] = audioBuffer;

    return audioBuffer;
}

async function loadInstrumentSample(instrument, sample) {
    const config = instrumentSamples[instrument] || instrumentSamples.piano;

    if (config.cache[sample.fileName]) {
        return config.cache[sample.fileName];
    }

    const audioContext = getAudioContext();
    const sampleUrl = `${config.basePath}/${encodeURIComponent(sample.fileName)}`;
    const response = await fetch(sampleUrl);

    if (!response.ok) {
        throw new Error(`Could not load ${instrument} sample: ${sample.fileName}`);
    }

    const arrayBuffer = await response.arrayBuffer();
    const audioBuffer = await audioContext.decodeAudioData(arrayBuffer);
    config.cache[sample.fileName] = audioBuffer;

    return audioBuffer;
}

async function playSampledInstrumentMidiNote(
    instrument,
    midi,
    startTime,
    duration = 1.6,
    gainAmount = null
) {
    const audioContext = getAudioContext();
    const config = instrumentSamples[instrument] || instrumentSamples.piano;
    const sample = getNearestInstrumentSample(instrument, midi);
    const gainValue = gainAmount ?? config.gain;

    try {
        const audioBuffer = await loadInstrumentSample(instrument, sample);
        const source = audioContext.createBufferSource();
        const gainNode = audioContext.createGain();
        const safeStartTime = getSafeAudioStartTime(audioContext, startTime);
        const safeEndTime = safeStartTime + duration;

        source.buffer = audioBuffer;
        source.playbackRate.value = Math.pow(2, (midi - sample.midi) / 12);

        gainNode.gain.setValueAtTime(0.001, safeStartTime);
        gainNode.gain.linearRampToValueAtTime(gainValue, safeStartTime + 0.025);
        gainNode.gain.exponentialRampToValueAtTime(0.001, safeEndTime);

        source.connect(gainNode);
        gainNode.connect(audioContext.destination);
        source.start(safeStartTime);
        source.stop(safeEndTime + 0.08);
    } catch (error) {
        console.warn(error);
        playFrequency(midiToFrequency(midi), audioContext.currentTime + 0.03, duration);
    }
}

async function playPianoMidiNote(midi, startTime, duration = 1.6, gainAmount = 0.42) {
    const audioContext = getAudioContext();
    const sample = getNearestPianoSample(midi);

    try {
        const audioBuffer = await loadPianoSample(sample);
        const source = audioContext.createBufferSource();
        const gainNode = audioContext.createGain();
        const safeStartTime = getSafeAudioStartTime(audioContext, startTime);
        const safeEndTime = safeStartTime + duration;

        source.buffer = audioBuffer;
        source.playbackRate.value = Math.pow(2, (midi - sample.midi) / 12);

        gainNode.gain.setValueAtTime(0.001, safeStartTime);
        gainNode.gain.linearRampToValueAtTime(gainAmount, safeStartTime + 0.025);
        gainNode.gain.exponentialRampToValueAtTime(0.001, safeEndTime);

        source.connect(gainNode);
        gainNode.connect(audioContext.destination);
        source.start(safeStartTime);
        source.stop(safeEndTime + 0.08);
    } catch (error) {
        console.warn(error);
        playFrequency(midiToFrequency(midi), audioContext.currentTime + 0.03, duration);
    }
}

function toVisualizerNote(note) {
    const normalized = normalizeNote(note);
    return enharmonicMap[normalized] || normalized;
}

let currentHighlightedNotes = [];
let currentExplanationContext = "";
let currentPlaybackNotes = [];
let currentProgression = [];
let songwritingHistory = [];
let earTrainingMode = "interval";
let currentEarQuestion = null;
let earScore = {
    correct: 0,
    total: 0
};

const intervalQuestions = [
    { label: "Minor 2nd", semitones: 1, tip: "A tense half-step, like two neighboring piano keys." },
    { label: "Major 2nd", semitones: 2, tip: "A whole-step sound, often like the first two notes of a scale." },
    { label: "Minor 3rd", semitones: 3, tip: "A darker three-semitone jump, common in minor melodies." },
    { label: "Major 3rd", semitones: 4, tip: "A bright four-semitone jump, like the bottom of a major chord." },
    { label: "Perfect 4th", semitones: 5, tip: "Open and stable, with a strong lift upward." },
    { label: "Tritone", semitones: 6, tip: "Unstable and spicy, exactly halfway across the octave." },
    { label: "Perfect 5th", semitones: 7, tip: "Wide, strong, and stable, like a power chord." },
    { label: "Octave", semitones: 12, tip: "The same note name higher up." }
];

const chordQuestions = [
    { label: "Major", intervals: [0, 4, 7], tip: "Bright and resolved, built from root, major third, and fifth." },
    { label: "Minor", intervals: [0, 3, 7], tip: "Darker and softer, built from root, minor third, and fifth." },
    { label: "Diminished", intervals: [0, 3, 6], tip: "Tense and narrow, with stacked minor thirds." },
    { label: "Augmented", intervals: [0, 4, 8], tip: "Dreamy and unsettled, with a raised fifth." },
    { label: "Major 7th", intervals: [0, 4, 7, 11], tip: "Bright and lush, with a dreamy major seventh on top." },
    { label: "Minor 7th", intervals: [0, 3, 7, 10], tip: "Warm and mellow, common in soul, R&B, jazz, and pop." },
    { label: "Dominant 7th", intervals: [0, 4, 7, 10], tip: "Bluesy and unresolved, with a major triad plus a flat seventh." },
    { label: "Major 9th", intervals: [0, 4, 7, 11, 14], tip: "Glossy and spacious, like a major seventh with an added ninth color." },
    { label: "Minor 9th", intervals: [0, 3, 7, 10, 14], tip: "Smooth and moody, like a minor seventh with an added ninth color." }
];

const theoryNoteToSemitone = {
    "C": 0,
    "C#": 1, "Db": 1,
    "D": 2,
    "D#": 3, "Eb": 3,
    "E": 4,
    "F": 5,
    "F#": 6, "Gb": 6,
    "G": 7,
    "G#": 8, "Ab": 8,
    "A": 9,
    "A#": 10, "Bb": 10,
    "B": 11
};

const semitoneToSharp = {
    0: "C",
    1: "C#",
    2: "D",
    3: "D#",
    4: "E",
    5: "F",
    6: "F#",
    7: "G",
    8: "G#",
    9: "A",
    10: "A#",
    11: "B"
};

const semitoneToFlat = {
    0: "C",
    1: "Db",
    2: "D",
    3: "Eb",
    4: "E",
    5: "F",
    6: "Gb",
    7: "G",
    8: "Ab",
    9: "A",
    10: "Bb",
    11: "B"
};

const majorKeySpellings = {
    "C": ["C", "D", "E", "F", "G", "A", "B"],
    "G": ["G", "A", "B", "C", "D", "E", "F#"],
    "D": ["D", "E", "F#", "G", "A", "B", "C#"],
    "A": ["A", "B", "C#", "D", "E", "F#", "G#"],
    "E": ["E", "F#", "G#", "A", "B", "C#", "D#"],
    "B": ["B", "C#", "D#", "E", "F#", "G#", "A#"],
    "F#": ["F#", "G#", "A#", "B", "C#", "D#", "E#"],
    "F": ["F", "G", "A", "Bb", "C", "D", "E"],
    "Bb": ["Bb", "C", "D", "Eb", "F", "G", "A"],
    "Eb": ["Eb", "F", "G", "Ab", "Bb", "C", "D"],
    "Ab": ["Ab", "Bb", "C", "Db", "Eb", "F", "G"],
    "Db": ["Db", "Eb", "F", "Gb", "Ab", "Bb", "C"],
    "Gb": ["Gb", "Ab", "Bb", "Cb", "Db", "Eb", "F"]
};

const minorKeySpellings = {
    "A": ["A", "B", "C", "D", "E", "F", "G"],
    "E": ["E", "F#", "G", "A", "B", "C", "D"],
    "B": ["B", "C#", "D", "E", "F#", "G", "A"],
    "F#": ["F#", "G#", "A", "B", "C#", "D", "E"],
    "C#": ["C#", "D#", "E", "F#", "G#", "A", "B"],
    "G#": ["G#", "A#", "B", "C#", "D#", "E", "F#"],
    "D": ["D", "E", "F", "G", "A", "Bb", "C"],
    "G": ["G", "A", "Bb", "C", "D", "Eb", "F"],
    "C": ["C", "D", "Eb", "F", "G", "Ab", "Bb"],
    "F": ["F", "G", "Ab", "Bb", "C", "Db", "Eb"],
    "Bb": ["Bb", "C", "Db", "Eb", "F", "Gb", "Ab"],
    "Eb": ["Eb", "F", "Gb", "Ab", "Bb", "Cb", "Db"]
};

const scalePatterns = {
    major: [2, 2, 1, 2, 2, 2, 1],
    minor: [2, 1, 2, 2, 1, 2, 2],
    natural_minor: [2, 1, 2, 2, 1, 2, 2],
    harmonic_minor: [2, 1, 2, 2, 1, 3, 1],
    melodic_minor: [2, 1, 2, 2, 2, 2, 1]
};

const chordPatterns = {
    major: [0, 4, 7],
    minor: [0, 3, 7],
    diminished: [0, 3, 6],
    augmented: [0, 4, 8],
    major7: [0, 4, 7, 11],
    minor7: [0, 3, 7, 10],
    dominant7: [0, 4, 7, 10],
    dim7: [0, 3, 6, 9]
};

const triadQualitiesMajor = ["major", "minor", "minor", "major", "major", "minor", "diminished"];
const triadQualitiesMinor = ["minor", "diminished", "major", "minor", "minor", "major", "major"];
const romanNumeralsMajor = ["I", "ii", "iii", "IV", "V", "vi", "vii°"];
const romanNumeralsMinor = ["i", "ii°", "III", "iv", "v", "VI", "VII"];
const commonProgressions = {
    pop: [1, 5, 6, 4],
    classic: [1, 4, 5, 1],
    jazz: [2, 5, 1],
    sad: [6, 4, 1, 5],
    minor_pop: [1, 6, 3, 7]
};

function normalizeNote(note) {
    return note.trim().charAt(0).toUpperCase() + note.trim().slice(1);
}

function raiseNote(note) {
    if (note.endsWith("b")) {
        return note.replace("b", "");
    }

    if (note.endsWith("#")) {
        return `${note}#`;
    }

    return `${note}#`;
}

function generateScaleNotes(root, scaleType = "major") {
    const normalizedRoot = normalizeNote(root);
    const normalizedScaleType = scaleType.trim().toLowerCase();

    if (!theoryNoteToSemitone.hasOwnProperty(normalizedRoot)) {
        throw new Error(`Invalid root note: ${normalizedRoot}`);
    }

    if (!scalePatterns.hasOwnProperty(normalizedScaleType)) {
        throw new Error(`Invalid scale type: ${normalizedScaleType}`);
    }

    if (normalizedScaleType === "major" && majorKeySpellings[normalizedRoot]) {
        return majorKeySpellings[normalizedRoot];
    }

    if (["minor", "natural_minor"].includes(normalizedScaleType) && minorKeySpellings[normalizedRoot]) {
        return minorKeySpellings[normalizedRoot];
    }

    const baseScale = minorKeySpellings[normalizedRoot];

    if (normalizedScaleType === "harmonic_minor" && baseScale) {
        const scale = [...baseScale];
        scale[6] = raiseNote(scale[6]);
        return scale;
    }

    if (normalizedScaleType === "melodic_minor" && baseScale) {
        const scale = [...baseScale];
        scale[5] = raiseNote(scale[5]);
        scale[6] = raiseNote(scale[6]);
        return scale;
    }

    throw new Error(`Proper spelling for ${normalizedRoot} ${normalizedScaleType} is not supported yet.`);
}

function prefersFlats(root) {
    return root.includes("b");
}

function generateChordNotes(root, chordType = "major") {
    const normalizedRoot = normalizeNote(root);
    const normalizedChordType = chordType.trim().toLowerCase();

    if (!theoryNoteToSemitone.hasOwnProperty(normalizedRoot)) {
        throw new Error(`Invalid root note: ${normalizedRoot}`);
    }

    if (!chordPatterns.hasOwnProperty(normalizedChordType)) {
        throw new Error(`Invalid chord type: ${normalizedChordType}`);
    }

    const rootValue = theoryNoteToSemitone[normalizedRoot];
    const spelling = prefersFlats(normalizedRoot) ? semitoneToFlat : semitoneToSharp;

    return chordPatterns[normalizedChordType].map(interval =>
        spelling[(rootValue + interval) % 12]
    );
}

function buildDiatonicChords(key, scaleType = "major") {
    const scale = generateScaleNotes(key, scaleType);
    const normalizedScaleType = scaleType.trim().toLowerCase();
    let qualities;
    let numerals;

    if (normalizedScaleType === "major") {
        qualities = triadQualitiesMajor;
        numerals = romanNumeralsMajor;
    } else if (["minor", "natural_minor"].includes(normalizedScaleType)) {
        qualities = triadQualitiesMinor;
        numerals = romanNumeralsMinor;
    } else {
        throw new Error("Only major and natural minor keys are supported for now.");
    }

    return scale.map((note, index) => {
        const quality = qualities[index];
        let symbol = note;

        if (quality === "minor") {
            symbol = `${note}m`;
        }

        if (quality === "diminished") {
            symbol = `${note}dim`;
        }

        return {
            degree: index + 1,
            roman_numeral: numerals[index],
            root: note,
            quality,
            symbol
        };
    });
}

function generateProgressionData(key, scaleType = "major", style = "pop") {
    const normalizedStyle = style.trim().toLowerCase();

    if (!commonProgressions.hasOwnProperty(normalizedStyle)) {
        throw new Error(`Invalid progression style: ${normalizedStyle}`);
    }

    const chords = buildDiatonicChords(key, scaleType);
    const degrees = commonProgressions[normalizedStyle];

    return {
        key,
        scale_type: scaleType,
        style: normalizedStyle,
        progression: degrees.map(degree => chords[degree - 1])
    };
}

function getNextNote(openNote, fret) {
    const startIndex = noteOrder.indexOf(openNote);
    const noteIndex = (startIndex + fret) % noteOrder.length;
    return noteOrder[noteIndex];
}

function buildPianoNotes(startOctave = 3, endOctave = 5) {
    const notes = [];

    for (let octave = startOctave; octave <= endOctave; octave++) {
        noteOrder.forEach(note => {
            notes.push({
                note,
                label: `${note}${octave}`,
                type: whiteNotes.includes(note) ? "white" : "black"
            });
        });
    }

    return notes;
}

function getPianoNotePath(root, notesToHighlight) {
    const pianoNotes = buildPianoNotes(3, 5);
    const normalizedRoot = toVisualizerNote(root);
    const normalizedNotes = notesToHighlight.map(note => toVisualizerNote(note));

    const rootIndex = pianoNotes.findIndex(item => item.note === normalizedRoot);

    if (rootIndex === -1) return [];

    const highlighted = [];
    let currentIndex = rootIndex;

    while (
        currentIndex < pianoNotes.length &&
        highlighted.length < normalizedNotes.length
    ) {
        const currentNote = pianoNotes[currentIndex];

        if (normalizedNotes.includes(currentNote.note)) {
            highlighted.push(currentNote.label);
        }

        currentIndex++;
    }

    return highlighted;
}

function createPiano(highlightedLabels = []) {
    const diagram = document.getElementById("diagram");
    diagram.innerHTML = "";

    const keyboard = document.createElement("div");
    keyboard.classList.add("keyboard");

    const pianoNotes = buildPianoNotes(3, 5);

    pianoNotes.forEach(item => {
        const key = document.createElement("div");
        key.classList.add("key", item.type);
        key.textContent = item.label;
        key.onclick = () => {
    playSingleNote(item.label);
};

        if (highlightedLabels.includes(item.label)) {
            key.classList.add("highlight");
        }

        keyboard.appendChild(key);
    });

    diagram.appendChild(keyboard);
}

function getCurrentVisualizerInstrument() {
    return document.getElementById("instrumentType").value;
}

function getVisualizerNoteMidi(note, defaultInstrument = getCurrentVisualizerInstrument()) {
    return getNoteMidi(note, visualizerDefaultOctaves[defaultInstrument] || 4);
}

function playVisualizerMidi(midi, duration = 1.45, gainAmount = null) {
    const instrument = getCurrentVisualizerInstrument();
    const context = getAudioContext();
    playSampledInstrumentMidiNote(instrument, midi, context.currentTime, duration, gainAmount);
}

function getFretPosition(instrument, stringIndex, fretNumber) {
    const config = fretboardConfigs[instrument];
    const midi = config.openMidis[stringIndex] + fretNumber;
    const note = noteOrder[midi % 12];

    return {
        stringIndex,
        fret: fretNumber,
        note,
        midi,
        key: `${stringIndex}:${fretNumber}`
    };
}

function getFretboardPositions(instrument) {
    const config = fretboardConfigs[instrument];
    const positions = [];

    config.strings.forEach((_, stringIndex) => {
        for (let fretNumber = 0; fretNumber <= config.frets; fretNumber++) {
            positions.push(getFretPosition(instrument, stringIndex, fretNumber));
        }
    });

    return positions;
}

function getChordToneIndex(note, chordNotes) {
    return chordNotes.findIndex(chordNote => toVisualizerNote(chordNote) === note);
}

function getVoicingScore(positions, chordNotes, windowStart, instrument, anchorPosition = null) {
    const frettedPositions = positions.filter(position => position.fret > 0);
    const uniqueNotes = new Set(positions.map(position => position.note));
    const targetNotes = new Set(chordNotes.map(note => toVisualizerNote(note)));
    const rootNote = toVisualizerNote(chordNotes[0]);
    const rootPosition = positions.find(position => position.note === rootNote);
    const frets = frettedPositions.map(position => position.fret);
    const span = frets.length ? Math.max(...frets) - Math.min(...frets) : 0;
    const coveragePenalty = (targetNotes.size - uniqueNotes.size) * 40;
    const missingRootPenalty = rootPosition ? 0 : 100;
    const mutedPenalty = (fretboardConfigs[instrument].strings.length - positions.length) * 3;
    const highFretPenalty = windowStart * 1.4;
    const spanPenalty = span * 5;
    const lowerStringRootBonus = rootPosition
        ? rootPosition.stringIndex * -2
        : 0;
    const anchorBonus = anchorPosition &&
        positions.some(position => position.key === anchorPosition.key)
        ? -80
        : 0;

    return coveragePenalty + missingRootPenalty + mutedPenalty + highFretPenalty + spanPenalty + lowerStringRootBonus + anchorBonus;
}

function getRootPositionOnString(instrument, stringIndex, rootNote) {
    const config = fretboardConfigs[instrument];
    const normalizedRoot = toVisualizerNote(rootNote);

    for (let fretNumber = 0; fretNumber <= config.frets; fretNumber++) {
        const position = getFretPosition(instrument, stringIndex, fretNumber);

        if (position.note === normalizedRoot) {
            return position;
        }
    }

    return null;
}

function getSelectedGuitarShapeAnchor() {
    const selector = document.getElementById("guitarShape");

    if (!selector) {
        return null;
    }

    return guitarShapeAnchors[selector.value] ?? guitarShapeAnchors.shape1;
}

function findPlayableVoicing(instrument, chordNotes, options = {}) {
    const config = fretboardConfigs[instrument];
    const targetNotes = [...new Set(chordNotes.map(note => toVisualizerNote(note)))];
    const requiredCoverage = Math.min(targetNotes.length, config.strings.length);
    const anchorPosition = Number.isInteger(options.anchorStringIndex)
        ? getRootPositionOnString(instrument, options.anchorStringIndex, chordNotes[0])
        : null;
    let bestVoicing = [];
    let bestScore = Infinity;

    for (let windowStart = 0; windowStart <= config.frets - config.maxSpan; windowStart++) {
        const windowEnd = windowStart + config.maxSpan;
        const candidatesByString = config.strings.map((_, stringIndex) => {
            const candidates = [];

            for (let fretNumber = 0; fretNumber <= config.frets; fretNumber++) {
                const inWindow = fretNumber >= windowStart && fretNumber <= windowEnd;
                const usableOpen = fretNumber === 0 && windowStart <= 2;

                if (!inWindow && !usableOpen) {
                    continue;
                }

                const position = getFretPosition(instrument, stringIndex, fretNumber);

                if (targetNotes.includes(position.note)) {
                    candidates.push(position);
                }
            }

            if (anchorPosition && stringIndex === anchorPosition.stringIndex) {
                const anchorInCandidates = candidates.some(position => position.key === anchorPosition.key);
                return anchorInCandidates ? [anchorPosition] : [];
            }

            return [null, ...candidates];
        });

        if (anchorPosition && candidatesByString[anchorPosition.stringIndex].length === 0) {
            continue;
        }

        function search(stringIndex, selected) {
            if (stringIndex === candidatesByString.length) {
                const selectedPositions = selected.filter(Boolean);

                if (!selectedPositions.length) {
                    return;
                }

                const coveredNotes = new Set(selectedPositions.map(position => position.note));

                if (coveredNotes.size < requiredCoverage || !coveredNotes.has(targetNotes[0])) {
                    return;
                }

                if (
                    anchorPosition &&
                    !selectedPositions.some(position => position.key === anchorPosition.key)
                ) {
                    return;
                }

                const score = getVoicingScore(selectedPositions, chordNotes, windowStart, instrument, anchorPosition);

                if (score < bestScore) {
                    bestScore = score;
                    bestVoicing = selectedPositions;
                }

                return;
            }

            candidatesByString[stringIndex].forEach(candidate => {
                search(stringIndex + 1, [...selected, candidate]);
            });
        }

        search(0, []);
    }

    if (bestVoicing.length) {
        return bestVoicing;
    }

    return getFretboardPositions(instrument)
        .filter(position => targetNotes.includes(position.note))
        .slice(0, requiredCoverage);
}

function getActiveFretboardVoicing(instrument) {
    const generatorType = document.getElementById("generatorType").value;
    const shouldUseVoicing =
        ["chord", "progression"].includes(generatorType) &&
        currentPlaybackNotes.length > 0;

    if (!shouldUseVoicing) {
        return [];
    }

    const options = instrument === "guitar" && generatorType === "chord"
        ? { anchorStringIndex: getSelectedGuitarShapeAnchor() }
        : {};

    return findPlayableVoicing(instrument, currentPlaybackNotes, options);
}

function createFretboard(instrument, highlightedNotes = [], voicingPositions = []) {
    const diagram = document.getElementById("diagram");
    diagram.innerHTML = "";
    const config = fretboardConfigs[instrument];
    const normalizedHighlights = highlightedNotes.map(note => toVisualizerNote(note));
    const voicingKeys = new Set(voicingPositions.map(position => position.key));
    const rootNote = currentPlaybackNotes[0]
        ? toVisualizerNote(currentPlaybackNotes[0])
        : toVisualizerNote(document.getElementById("rootNote").value || "C");
    const useVoicing = voicingKeys.size > 0;

    const fretboard = document.createElement("div");
    fretboard.classList.add("fretboard");

    const fretNumbers = document.createElement("div");
    fretNumbers.classList.add("fret-numbers");
    const tuningLabel = document.createElement("span");
    tuningLabel.textContent = "Open";
    fretNumbers.appendChild(tuningLabel);

    for (let fretNumber = 1; fretNumber <= config.frets; fretNumber++) {
        const label = document.createElement("span");
        label.textContent = fretNumber;
        fretNumbers.appendChild(label);
    }

    const neck = document.createElement("div");
    neck.classList.add("fretboard-neck", `${instrument}-neck`);
    neck.appendChild(fretNumbers);

    config.strings.forEach((openString, stringIndex) => {
        const row = document.createElement("div");
        row.classList.add("string-row");

        const openPosition = getFretPosition(instrument, stringIndex, 0);
        const openIsVoiced = voicingKeys.has(openPosition.key);
        const openIsHighlighted = useVoicing
            ? openIsVoiced
            : normalizedHighlights.includes(openPosition.note);
        const openToneIndex = getChordToneIndex(openPosition.note, currentPlaybackNotes);

        const stringName = document.createElement("button");
        stringName.classList.add("string-name");
        stringName.type = "button";
        stringName.textContent = openString;
        stringName.setAttribute("aria-label", `${config.label} open ${openString} string, ${getDisplayNote(openPosition.note)}`);
        stringName.onclick = () => {
            playVisualizerMidi(openPosition.midi);
        };

        if (openIsHighlighted) {
            stringName.classList.add("highlight");
        }

        if (openIsVoiced) {
            stringName.classList.add("voiced");
        }

        if (openIsHighlighted && openPosition.note === rootNote) {
            stringName.classList.add("root-note");
        }

        if (openIsHighlighted) {
            const marker = document.createElement("span");
            marker.classList.add("note-marker");
            marker.textContent = getDisplayNote(openPosition.note);

            if (openToneIndex >= 0) {
                marker.style.setProperty("--tone-index", openToneIndex);
            }

            stringName.innerHTML = "";
            stringName.appendChild(marker);
        }

        row.appendChild(stringName);

        for (let fretNumber = 1; fretNumber <= config.frets; fretNumber++) {
            const position = getFretPosition(instrument, stringIndex, fretNumber);
            const isVoiced = voicingKeys.has(position.key);
            const isHighlighted = useVoicing
                ? isVoiced
                : normalizedHighlights.includes(position.note);
            const toneIndex = getChordToneIndex(position.note, currentPlaybackNotes);

            const fret = document.createElement("button");
            fret.classList.add("fret");
            fret.type = "button";
            fret.setAttribute("aria-label", `${config.label} ${openString} string fret ${fretNumber}, ${getDisplayNote(position.note)}`);
            fret.onclick = () => {
                playVisualizerMidi(position.midi);
            };

            if (isHighlighted) {
                fret.classList.add("highlight");
            }

            if (isVoiced) {
                fret.classList.add("voiced");
            }

            if (isHighlighted && position.note === rootNote) {
                fret.classList.add("root-note");
            }

            if ([3, 5, 7, 9, 12].includes(fretNumber)) {
                fret.classList.add("marker-fret");
            }

            if (isHighlighted) {
                const marker = document.createElement("span");
                marker.classList.add("note-marker");
                marker.textContent = getDisplayNote(position.note);

                if (toneIndex >= 0) {
                    marker.style.setProperty("--tone-index", toneIndex);
                }

                fret.appendChild(marker);
            }

            row.appendChild(fret);
        }

        neck.appendChild(row);
    });

    const legend = document.createElement("div");
    legend.classList.add("fretboard-legend");
    legend.textContent = useVoicing
        ? "Playable chord shape highlighted. The tuning labels are open strings."
        : "Generated notes appear across the neck. The tuning labels are open strings.";

    fretboard.appendChild(neck);
    fretboard.appendChild(legend);
    diagram.appendChild(fretboard);
}

function refreshDiagram() {
    const instrument = document.getElementById("instrumentType").value;
    const root = normalizeNote(document.getElementById("rootNote").value || "C");

    if (instrument === "piano") {
        const labels = getPianoNotePath(root, currentHighlightedNotes);
        createPiano(labels);
    }

    if (instrument === "guitar") {
        createFretboard(instrument, currentHighlightedNotes, getActiveFretboardVoicing(instrument));
    }

    if (instrument === "bass") {
        createFretboard(instrument, currentHighlightedNotes, getActiveFretboardVoicing(instrument));
    }
}

function updateGeneratorControls() {
    const generatorType = document.getElementById("generatorType").value;
    const instrument = document.getElementById("instrumentType").value;
    const scaleTypeWrapper = document.getElementById("scaleTypeWrapper");
    const chordTypeWrapper = document.getElementById("chordTypeWrapper");
    const progressionStyleWrapper = document.getElementById("progressionStyleWrapper");
    const inversionWrapper = document.getElementById("inversionWrapper");

    scaleTypeWrapper.style.display = "none";
    chordTypeWrapper.style.display = "none";
    progressionStyleWrapper.style.display = "none";
    inversionWrapper.style.display = "none";

    if (generatorType === "scale") {
        scaleTypeWrapper.style.display = "flex";
    }

    if (generatorType === "chord") {
        chordTypeWrapper.style.display = "flex";

        if (instrument === "guitar") {
            inversionWrapper.style.display = "flex";
        }
    }

    if (generatorType === "progression") {
        scaleTypeWrapper.style.display = "flex";
        progressionStyleWrapper.style.display = "flex";
    }
}

function toggleGenerator() {
    updateGeneratorControls();

    document.getElementById("result").textContent = "";
    document.getElementById("progressionChords").innerHTML = "";
    document.getElementById("aiExplanation").textContent =
        "Generate something, then click Explain This.";

    currentHighlightedNotes = [];
    refreshDiagram();
}

function handleInstrumentChange() {
    updateGeneratorControls();
    refreshDiagram();
}

async function generate() {
    const generatorType = document.getElementById("generatorType").value;

    if (generatorType === "scale") {
        await generateScale();
    }

    if (generatorType === "chord") {
        await generateChord();
    }

    if (generatorType === "progression") {
        await generateProgression();
    }
}

async function generateScale() {
    document.getElementById("progressionChords").innerHTML = "";
    const root = normalizeNote(document.getElementById("rootNote").value);
    const scaleType = document.getElementById("scaleType").value;

    try {
        const notes = generateScaleNotes(root, scaleType);

        currentHighlightedNotes = notes.map(note => toVisualizerNote(note));
        currentPlaybackNotes = notes;
        currentProgression = [];

        document.getElementById("result").textContent =
            `${root} ${scaleType}: ${notes.join(", ")}`;

        currentExplanationContext =
            `Explain the ${root} ${scaleType} scale. The notes are ${notes.join(", ")}. Explain it for a beginner.`;

        refreshDiagram();
    } catch (error) {
        document.getElementById("result").textContent = error.message;
        currentHighlightedNotes = [];
        currentPlaybackNotes = [];
        currentProgression = [];
        refreshDiagram();
    }
}

async function generateChord() {
    document.getElementById("progressionChords").innerHTML = "";
    const root = normalizeNote(document.getElementById("rootNote").value);
    const chordType = document.getElementById("chordType").value;

    try {
        const notes = generateChordNotes(root, chordType);

        currentHighlightedNotes = notes.map(note => toVisualizerNote(note));
        currentPlaybackNotes = notes;
        currentProgression = [];

        document.getElementById("result").textContent =
            `${root} ${chordType}: ${notes.join(", ")}`;

        currentExplanationContext =
            `Explain the ${root} ${chordType} chord. The notes are ${notes.join(", ")}. Explain how this chord is built for a beginner.`;

        refreshDiagram();
    } catch (error) {
        document.getElementById("result").textContent = error.message;
        currentHighlightedNotes = [];
        currentPlaybackNotes = [];
        currentProgression = [];
        refreshDiagram();
    }
}

async function generateProgression() {
    const key = normalizeNote(document.getElementById("rootNote").value);
    const scaleType = document.getElementById("scaleType").value || "major";
    const style = document.getElementById("progressionStyle").value;

    try {
        const data = generateProgressionData(key, scaleType, style);

        document.getElementById("result").textContent =
            `${data.key} ${data.scale_type} ${data.style} progression`;

        renderProgressionButtons(data.progression);
        currentProgression = data.progression;
        currentPlaybackNotes = [];

        const progressionText = data.progression
        .map(chord => `${chord.roman_numeral}: ${chord.symbol}`)
        .join(", ");

        currentExplanationContext =
        `Explain this ${data.key} ${data.scale_type} ${data.style} chord progression: ${progressionText}. Explain why it works for a beginner.`;
    } catch (error) {
        document.getElementById("result").textContent = error.message;
        document.getElementById("progressionChords").innerHTML = "";
        currentHighlightedNotes = [];
        currentPlaybackNotes = [];
        currentProgression = [];
        refreshDiagram();
    }
}

function renderProgressionButtons(progression) {
    const container = document.getElementById("progressionChords");
    container.innerHTML = "";
    container.classList.add("progression-chords");

    progression.forEach(chord => {
        const button = document.createElement("button");
        button.classList.add("progression-button");
        button.textContent = `${chord.roman_numeral}: ${chord.symbol}`;

        button.onclick = async () => {
            document.querySelectorAll(".progression-button").forEach(btn => {
                btn.classList.remove("active");
            });

            button.classList.add("active");

            await highlightProgressionChord(chord);
        };

        container.appendChild(button);
    });
}

async function highlightProgressionChord(chord) {
    try {
        const notes = generateChordNotes(chord.root, chord.quality);

        currentHighlightedNotes = notes.map(note => toVisualizerNote(note));
        currentPlaybackNotes = notes;

        document.getElementById("result").textContent =
            `${chord.roman_numeral}: ${chord.symbol} = ${notes.join(", ")}`;

        currentExplanationContext =
        `Explain the ${chord.symbol} chord in this progression. It is the ${chord.roman_numeral} chord and contains the notes ${notes.join(", ")}. Explain its function for a beginner.`;
        refreshDiagram();
    } catch (error) {
        document.getElementById("result").textContent = error.message;
        currentHighlightedNotes = [];
        currentPlaybackNotes = [];
        refreshDiagram();
    }
}

async function explainCurrentSelection() {
    const explanationBox = document.getElementById("aiExplanation");

    if (!currentExplanationContext) {
        explanationBox.textContent =
            "Generate a scale, chord, or progression first.";
        return;
    }

    explanationBox.textContent = "Thinking...";

    const response = await fetch(`${API_URL}/chat`, {
        method: "POST",
        headers: {
            "Content-Type": "application/json"
        },
        body: JSON.stringify({
            message: currentExplanationContext
        })
    });

    const data = await response.json();

    if (!response.ok) {
        explanationBox.textContent =
            data.detail || "Something went wrong.";
        return;
    }

    await typeMessage(explanationBox, data.response);
}

function playNote(note, startTime, duration = 0.5) {
    const audioContext = new (window.AudioContext || window.webkitAudioContext)();
    const oscillator = audioContext.createOscillator();
    const gainNode = audioContext.createGain();

    oscillator.type = "sine";
    oscillator.frequency.value = noteFrequencies[note];

    oscillator.connect(gainNode);
    gainNode.connect(audioContext.destination);

    gainNode.gain.setValueAtTime(0.2, startTime);
    gainNode.gain.exponentialRampToValueAtTime(0.001, startTime + duration);

    oscillator.start(startTime);
    oscillator.stop(startTime + duration);
}

function playNotesSequentially(notes) {
    const audioContext = getAudioContext();
    const instrument = getCurrentVisualizerInstrument();

    notes.forEach((note, index) => {
        const midi = getVisualizerNoteMidi(note, instrument);
        const startTime = audioContext.currentTime + index * 0.52;

        if (midi === null) {
            playFrequency(noteFrequencies[note], startTime, 0.7);
            return;
        }

        playSampledInstrumentMidiNote(instrument, midi, startTime, 1.25, 0.4);
    });
}

function playFrequency(frequency, startTime, duration = 0.65) {
    if (!frequency) {
        return;
    }

    const audioContext = getAudioContext();
    const safeStartTime = getSafeAudioStartTime(audioContext, startTime);
    const safeEndTime = safeStartTime + duration;
    const oscillator = audioContext.createOscillator();
    const gainNode = audioContext.createGain();

    oscillator.type = "sine";
    oscillator.frequency.value = frequency;

    oscillator.connect(gainNode);
    gainNode.connect(audioContext.destination);

    gainNode.gain.setValueAtTime(0.001, safeStartTime);
    gainNode.gain.linearRampToValueAtTime(0.22, safeStartTime + 0.03);
    gainNode.gain.exponentialRampToValueAtTime(0.001, safeEndTime);

    oscillator.start(safeStartTime);
    oscillator.stop(safeEndTime);
}

function playSingleNote(noteWithOctave) {
    const instrument = getCurrentVisualizerInstrument();
    const midi = getNoteMidi(noteWithOctave, visualizerDefaultOctaves[instrument] || 4);

    if (midi === null) {
        const frequency = getNoteFrequency(noteWithOctave);

        if (!frequency) {
            console.log("No frequency found for:", noteWithOctave);
            return;
        }

        const context = getAudioContext();
        playFrequency(frequency, context.currentTime, 0.8);
        return;
    }

    const context = getAudioContext();
    playSampledInstrumentMidiNote(instrument, midi, context.currentTime, 1.35, 0.42);
}

function playChord(notes) {
    const audioContext = getAudioContext();
    const instrument = getCurrentVisualizerInstrument();
    const generatorType = document.getElementById("generatorType").value;

    if (
        ["guitar", "bass"].includes(instrument) &&
        ["chord", "progression"].includes(generatorType)
    ) {
        const options = instrument === "guitar" && generatorType === "chord"
            ? { anchorStringIndex: getSelectedGuitarShapeAnchor() }
            : {};
        const voicing = findPlayableVoicing(instrument, notes, options)
            .sort((a, b) => b.stringIndex - a.stringIndex);

        voicing.forEach((position, index) => {
            const startTime = audioContext.currentTime + index * 0.035;
            playSampledInstrumentMidiNote(instrument, position.midi, startTime, 1.8, 0.34);
        });

        return;
    }

    notes.forEach((note, index) => {
        const midi = getVisualizerNoteMidi(note, instrument);
        const startTime = audioContext.currentTime + index * 0.018;

        if (midi === null) {
            playFrequency(noteFrequencies[note], startTime, 1.2);
            return;
        }

        playSampledInstrumentMidiNote(instrument, midi, startTime, 1.8, 0.34);
    });
}

async function playCurrentSelection() {
    if (currentPlaybackNotes.length === 0 && currentProgression.length === 0) {
        alert("Generate a scale, chord, or progression first.");
        return;
    }

    const generatorType = document.getElementById("generatorType").value;

    if (generatorType === "scale") {
        playNotesSequentially(currentPlaybackNotes);
    }

    if (generatorType === "chord") {
        playChord(currentPlaybackNotes);
    }

    if (generatorType === "progression") {
        await playProgression();
    }
}

async function playProgression() {
    for (let i = 0; i < currentProgression.length; i++) {
        const chord = currentProgression[i];
        const notes = generateChordNotes(chord.root, chord.quality);

        setTimeout(() => {
            playChord(notes);
        }, i * 1300);
    }
}

async function sendChatMessage() {
    const input = document.getElementById("chatInput");

    const userMessage = input.value.trim();

    if (!userMessage) {
        return;
    }

    addChatMessage(userMessage, "user-message");
    input.value = "";

    const aiMessageElement = createTypingIndicator();

    const response = await fetch(`${API_URL}/chat`, {
        method: "POST",
        headers: {
            "Content-Type": "application/json"
        },
        body: JSON.stringify({
            message: userMessage
        })
    });

    const data = await response.json();

    if (!response.ok) {
        aiMessageElement.textContent =
            data.detail || "Something went wrong.";
        return;
    }

    aiMessageElement.innerHTML = "";

    await typeMessage(aiMessageElement, data.response);
}

function showAppView(viewName) {
    const songwritingScreen = document.getElementById("songwriting");
    const earTrainingScreen = document.getElementById("earTraining");
    const jamScreen = document.getElementById("jam");
    const theoryWorkspace = document.getElementById("theoryWorkspace");

    document.body.classList.toggle("songwriting-active", viewName === "songwriting");
    document.body.classList.toggle(
        "focused-tool-active",
        ["songwriting", "ear-training", "visualizer", "jam"].includes(viewName)
    );

    document.querySelectorAll(".bottom-nav-link").forEach(link => {
        link.classList.toggle("active", link.dataset.view === viewName);
    });

    if (viewName === "songwriting") {
        songwritingScreen.classList.add("active-view");
        earTrainingScreen.classList.remove("active-view");
        jamScreen.classList.remove("active-view");
        theoryWorkspace.classList.remove("active-view");
        document.getElementById("songwritingInput").focus();
        return;
    }

    if (viewName === "ear-training") {
        songwritingScreen.classList.remove("active-view");
        theoryWorkspace.classList.remove("active-view");
        earTrainingScreen.classList.add("active-view");
        jamScreen.classList.remove("active-view");

        if (!currentEarQuestion) {
            newEarQuestion();
        }

        return;
    }

    if (viewName === "jam") {
        songwritingScreen.classList.remove("active-view");
        earTrainingScreen.classList.remove("active-view");
        theoryWorkspace.classList.remove("active-view");
        jamScreen.classList.add("active-view");
        return;
    }

    songwritingScreen.classList.remove("active-view");
    earTrainingScreen.classList.remove("active-view");
    jamScreen.classList.remove("active-view");
    theoryWorkspace.classList.add("active-view");

    if (viewName === "visualizer") {
        document.getElementById("visualizer").scrollIntoView({
            behavior: "smooth",
            block: "start"
        });
    }
}

function setEarTrainingMode(mode) {
    earTrainingMode = mode;

    document.querySelectorAll(".ear-mode-button").forEach(button => {
        button.classList.toggle("active", button.dataset.earMode === mode);
    });

    newEarQuestion();
}

function newEarQuestion() {
    const questionBank = earTrainingMode === "interval" ? intervalQuestions : chordQuestions;
    const answer = questionBank[Math.floor(Math.random() * questionBank.length)];
    const rootIndex = Math.floor(Math.random() * noteOrder.length);
    const root = noteOrder[rootIndex];
    const rootOctave = earTrainingMode === "interval"
        ? 3 + Math.floor(Math.random() * 2)
        : 3;
    const rootMidi = getMidiNote(root, rootOctave);
    const rootFrequency = midiToFrequency(rootMidi);

    currentEarQuestion = {
        mode: earTrainingMode,
        root,
        rootMidi,
        rootFrequency,
        answer,
        answered: false
    };

    if (earTrainingMode === "interval") {
        currentEarQuestion.targetMidi = rootMidi + answer.semitones;
        currentEarQuestion.targetFrequency =
            rootFrequency * Math.pow(2, answer.semitones / 12);
    } else {
        currentEarQuestion.chordMidis = answer.intervals.map(interval =>
            rootMidi + interval
        );
        currentEarQuestion.frequencies = answer.intervals.map(interval =>
            rootFrequency * Math.pow(2, interval / 12)
        );
    }

    document.getElementById("earPrompt").textContent =
        earTrainingMode === "interval"
            ? "Play two notes, then choose the interval you hear."
            : "Play the chord, then choose the chord quality you hear.";

    document.getElementById("earQuestionLabel").textContent =
        earTrainingMode === "interval" ? "Interval Question" : "Chord Question";

    document.getElementById("earStatus").className = "ear-status";
    document.getElementById("earStatus").textContent = "Press Play to hear the question.";
    document.getElementById("earExplanation").textContent =
        "Answer a question, then ask for a short listening tip.";

    renderEarAnswerButtons();
}

function renderEarAnswerButtons() {
    const grid = document.getElementById("earAnswerGrid");
    const questionBank = earTrainingMode === "interval" ? intervalQuestions : chordQuestions;

    grid.innerHTML = "";

    questionBank.forEach(answer => {
        const button = document.createElement("button");
        button.classList.add("ear-answer-button");
        button.type = "button";
        button.textContent = answer.label;
        button.onclick = () => answerEarQuestion(answer.label);
        grid.appendChild(button);
    });
}

async function playEarQuestion() {
    if (!currentEarQuestion) {
        newEarQuestion();
    }

    const audioContext = getAudioContext();
    const now = audioContext.currentTime + 0.05;

    if (currentEarQuestion.mode === "interval") {
        await playPianoMidiNote(currentEarQuestion.rootMidi, now, 1.2, 0.42);
        await playPianoMidiNote(currentEarQuestion.targetMidi, now + 0.82, 1.35, 0.42);
        return;
    }

    currentEarQuestion.chordMidis.forEach((midi, index) => {
        playPianoMidiNote(midi, now + index * 0.018, 1.9, 0.34);
    });
}

function answerEarQuestion(answerLabel) {
    if (!currentEarQuestion || currentEarQuestion.answered) {
        return;
    }

    const isCorrect = answerLabel === currentEarQuestion.answer.label;
    const status = document.getElementById("earStatus");

    currentEarQuestion.answered = true;
    earScore.total += 1;

    if (isCorrect) {
        earScore.correct += 1;
        status.className = "ear-status correct";
        status.textContent = `Correct. ${currentEarQuestion.answer.label}: ${currentEarQuestion.answer.tip}`;
    } else {
        status.className = "ear-status incorrect";
        status.textContent =
            `Not quite. The answer was ${currentEarQuestion.answer.label}. ${currentEarQuestion.answer.tip}`;
    }

    document.querySelectorAll(".ear-answer-button").forEach(button => {
        button.disabled = true;

        if (button.textContent === currentEarQuestion.answer.label) {
            button.classList.add("correct");
        }

        if (!isCorrect && button.textContent === answerLabel) {
            button.classList.add("incorrect");
        }
    });

    updateEarScore();
}

function updateEarScore() {
    document.getElementById("earScore").textContent =
        `${earScore.correct} / ${earScore.total}`;
}

async function explainEarQuestion() {
    const explanation = document.getElementById("earExplanation");

    if (!currentEarQuestion) {
        explanation.textContent = "Start an ear training question first.";
        return;
    }

    explanation.textContent = "Thinking...";

    const questionType = currentEarQuestion.mode === "interval"
        ? `the ${currentEarQuestion.answer.label} interval`
        : `a ${currentEarQuestion.answer.label} chord`;

    const response = await fetch(`${API_URL}/chat`, {
        method: "POST",
        headers: {
            "Content-Type": "application/json"
        },
        body: JSON.stringify({
            message:
                `Explain how to recognize ${questionType} by ear. ` +
                `Use beginner-friendly listening cues, one familiar musical association, and a short practice tip. ` +
                `Keep it concise.`
        })
    });

    const data = await response.json();

    if (!response.ok) {
        explanation.textContent = data.detail || "Something went wrong.";
        return;
    }

    await typeMessage(explanation, data.response);
}

function openSongwritingConversation() {
    const composer = document.getElementById("songwritingComposer");
    const messages = document.getElementById("songwritingMessages");

    composer.classList.add("open");

    if (!messages.children.length) {
        addSongwritingMessage(
            "Tell me the mood, genre, artist inspiration, story, or rough lyric idea. I can help shape melody, harmony, lyrical themes, structure, and next steps.",
            "ai"
        );
    }
}

function closeSongwritingConversation() {
    document.getElementById("songwritingComposer").classList.remove("open");
    document.getElementById("songwritingInput").focus();
}

async function sendSongwritingMessage(event) {
    event.preventDefault();

    const input = document.getElementById("songwritingInput");
    const userMessage = input.value.trim();

    if (!userMessage) {
        return;
    }

    openSongwritingConversation();
    addSongwritingMessage(userMessage, "user");
    songwritingHistory.push({ role: "User", content: userMessage });
    input.value = "";

    const aiMessageElement = addSongwritingTypingIndicator();
    const context = songwritingHistory
        .slice(-8)
        .map(entry => `${entry.role}: ${entry.content}`)
        .join("\n");

    const response = await fetch(`${API_URL}/chat`, {
        method: "POST",
        headers: {
            "Content-Type": "application/json"
        },
        body: JSON.stringify({
            message:
                "You are an experienced songwriter and creative collaborator. " +
                "Help the user write a song with practical suggestions for melody, harmony, rhythm, song structure, lyrical themes, title ideas, and next-step exercises. " +
                "Be specific, encouraging, and concise. Ask one useful follow-up question when needed.\n\n" +
                `Conversation so far:\n${context}\n\nRespond to the latest user message as the songwriter.`
        })
    });

    const data = await response.json();

    if (!response.ok) {
        aiMessageElement.textContent =
            data.detail || "Something went wrong.";
        return;
    }

    aiMessageElement.innerHTML = "";
    songwritingHistory.push({ role: "Songwriting Assistant", content: data.response });

    await typeSongwritingMessage(aiMessageElement, data.response);
}

function addSongwritingMessage(text, type) {
    const messages = document.getElementById("songwritingMessages");
    const message = document.createElement("div");
    message.classList.add("songwriting-message", type);
    message.textContent = text;
    messages.appendChild(message);
    messages.scrollTop = messages.scrollHeight;
    return message;
}

function addSongwritingTypingIndicator() {
    const message = addSongwritingMessage("", "ai");
    const typing = document.createElement("div");
    typing.classList.add("typing-indicator");

    for (let i = 0; i < 3; i++) {
        const dot = document.createElement("div");
        dot.classList.add("typing-dot");
        typing.appendChild(dot);
    }

    message.appendChild(typing);
    return message;
}

async function typeSongwritingMessage(element, text) {
    const messages = document.getElementById("songwritingMessages");
    element.textContent = "";

    for (let i = 0; i < text.length; i++) {
        element.textContent += text[i];
        messages.scrollTop = messages.scrollHeight;
        await new Promise(resolve => setTimeout(resolve, 10));
    }
}

async function typeMessage(element, text) {
    element.textContent = "";

    for (let i = 0; i < text.length; i++) {
        element.textContent += text[i];

        const chatMessages = document.getElementById("chatMessages");
        chatMessages.scrollTop = chatMessages.scrollHeight;

        await new Promise(resolve => setTimeout(resolve, 12));
    }
}

function addChatMessage(text, className) {
    const chatMessages = document.getElementById("chatMessages");

    const message = document.createElement("div");
    message.classList.add("chat-message", className);
    message.textContent = text;

    chatMessages.appendChild(message);
    chatMessages.scrollTop = chatMessages.scrollHeight;

    return message;
}

function createTypingIndicator() {
    const chatMessages = document.getElementById("chatMessages");

    const message = document.createElement("div");
    message.classList.add("chat-message", "ai-message");

    const typing = document.createElement("div");
    typing.classList.add("typing-indicator");

    for (let i = 0; i < 3; i++) {
        const dot = document.createElement("div");
        dot.classList.add("typing-dot");
        typing.appendChild(dot);
    }

    message.appendChild(typing);

    chatMessages.appendChild(message);
    chatMessages.scrollTop = chatMessages.scrollHeight;

    return message;
}

document.getElementById("chatInput").addEventListener("keydown", function(event) {
    if (event.key === "Enter") {
        sendChatMessage();
    }
});

document.querySelectorAll(".bottom-nav-link").forEach(link => {
    link.addEventListener("click", function(event) {
        event.preventDefault();
        showAppView(this.dataset.view);
    });
});

document.getElementById("songwritingInput").addEventListener("focus", function() {
    showAppView("songwriting");
});

document.querySelectorAll(".ear-mode-button").forEach(button => {
    button.addEventListener("click", function() {
        setEarTrainingMode(this.dataset.earMode);
    });
});

document.getElementById("earPlayButton").addEventListener("click", playEarQuestion);
document.getElementById("earNewQuestionButton").addEventListener("click", newEarQuestion);
document.getElementById("earExplainButton").addEventListener("click", explainEarQuestion);

function routeFromHash() {
    const routes = {
        "#songwriting": "songwriting",
        "#ear-training": "ear-training",
        "#jam": "jam",
        "#visualizer": "visualizer"
    };

    showAppView(routes[window.location.hash] || "songwriting");
}

window.addEventListener("hashchange", routeFromHash);
routeFromHash();

function getNoteFrequency(noteWithOctave) {
    const match = noteWithOctave.match(/^([A-G]#?)(\d)$/);

    if (!match) {
        const fallbackNote = noteWithOctave.replace(/[0-9]/g, "");
        return noteFrequencies[fallbackNote];
    }

    const note = match[1];
    const octave = parseInt(match[2]);

    const semitoneFromA4 = {
        "C": -9,
        "C#": -8,
        "D": -7,
        "D#": -6,
        "E": -5,
        "F": -4,
        "F#": -3,
        "G": -2,
        "G#": -1,
        "A": 0,
        "A#": 1,
        "B": 2
    };

    return 440 * Math.pow(2, (semitoneFromA4[note] + 12 * (octave - 4)) / 12);
}

refreshDiagram();
