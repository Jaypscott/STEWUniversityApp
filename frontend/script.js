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

function toVisualizerNote(note) {
    const normalized = normalizeNote(note);
    return enharmonicMap[normalized] || normalized;
}

let currentHighlightedNotes = [];
let currentExplanationContext = "";
let currentPlaybackNotes = [];
let currentProgression = [];

function normalizeNote(note) {
    return note.trim().charAt(0).toUpperCase() + note.trim().slice(1);
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

function createFretboard(strings, highlightedNotes = []) {
    const diagram = document.getElementById("diagram");
    diagram.innerHTML = "";

    const fretboard = document.createElement("div");
    fretboard.classList.add("fretboard");

    strings.forEach(openString => {
        const row = document.createElement("div");
        row.classList.add("string-row");

        const stringName = document.createElement("div");
        stringName.classList.add("string-name");
        stringName.textContent = openString;

        row.appendChild(stringName);

        for (let fretNumber = 0; fretNumber <= 12; fretNumber++) {
            const note = getNextNote(openString, fretNumber);

            const fret = document.createElement("div");
            fret.classList.add("fret");
            fret.textContent = `${note}`;
            fret.onclick = () => {
    playSingleNote(note);
};

            if (highlightedNotes.includes(note)) {
                fret.classList.add("highlight");
            }

            row.appendChild(fret);
        }

        fretboard.appendChild(row);
    });

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
        createFretboard(guitarStrings, currentHighlightedNotes);
    }

    if (instrument === "bass") {
        createFretboard(bassStrings, currentHighlightedNotes);
    }
}

function toggleGenerator() {
    const generatorType = document.getElementById("generatorType").value;
    const scaleTypeWrapper = document.getElementById("scaleTypeWrapper");
    const chordTypeWrapper = document.getElementById("chordTypeWrapper");
    const progressionStyleWrapper = document.getElementById("progressionStyleWrapper");

    scaleTypeWrapper.style.display = "none";
    chordTypeWrapper.style.display = "none";
    progressionStyleWrapper.style.display = "none";

    if (generatorType === "scale") {
        scaleTypeWrapper.style.display = "flex";
    }

    if (generatorType === "chord") {
        chordTypeWrapper.style.display = "flex";
    }

    if (generatorType === "progression") {
        scaleTypeWrapper.style.display = "flex";
        progressionStyleWrapper.style.display = "flex";
    }

    document.getElementById("result").textContent = "";
    document.getElementById("progressionChords").innerHTML = "";
    document.getElementById("aiExplanation").textContent =
        "Generate something, then click Explain This.";

    currentHighlightedNotes = [];
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

    const response = await fetch(`${API_URL}/scales`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ root, scale_type: scaleType })
    });

    const data = await response.json();

    if (!response.ok) {
        document.getElementById("result").textContent = data.detail;
        currentHighlightedNotes = [];
        refreshDiagram();
        return;
    }

    currentHighlightedNotes = data.notes.map(note => toVisualizerNote(note));
    currentPlaybackNotes = data.notes;
    currentProgression = [];

    document.getElementById("result").textContent =
        `${data.root} ${data.scale_type}: ${data.notes.join(", ")}`;
    
    currentExplanationContext =
    `Explain the ${data.root} ${data.scale_type} scale. The notes are ${data.notes.join(", ")}. Explain it for a beginner.`;

    refreshDiagram();
}

async function generateChord() {
    document.getElementById("progressionChords").innerHTML = "";
    const root = normalizeNote(document.getElementById("rootNote").value);
    const chordType = document.getElementById("chordType").value;

    const response = await fetch(`${API_URL}/chords`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ root, chord_type: chordType })
    });

    const data = await response.json();

    if (!response.ok) {
        document.getElementById("result").textContent = data.detail;
        currentHighlightedNotes = [];
        refreshDiagram();
        return;
    }

    currentHighlightedNotes = data.notes.map(note => toVisualizerNote(note));
    currentPlaybackNotes = data.notes;
    currentProgression = [];

    document.getElementById("result").textContent =
        `${data.root} ${data.chord_type}: ${data.notes.join(", ")}`;

    currentExplanationContext =
    `Explain the ${data.root} ${data.chord_type} chord. The notes are ${data.notes.join(", ")}. Explain how this chord is built for a beginner.`;

    refreshDiagram();
}

async function generateProgression() {
    const key = normalizeNote(document.getElementById("rootNote").value);
    const scaleType = document.getElementById("scaleType").value || "major";
    const style = document.getElementById("progressionStyle").value;

    const response = await fetch(`${API_URL}/progressions`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
            key: key,
            scale_type: scaleType,
            style: style
        })
    });

    const data = await response.json();

    if (!response.ok) {
        document.getElementById("result").textContent = data.detail;
        document.getElementById("progressionChords").innerHTML = "";
        currentHighlightedNotes = [];
        refreshDiagram();
        return;
    }

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
    const response = await fetch(`${API_URL}/chords`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
            root: chord.root,
            chord_type: chord.quality
        })
    });

    const data = await response.json();

    if (!response.ok) {
        document.getElementById("result").textContent = data.detail;
        currentHighlightedNotes = [];
        refreshDiagram();
        return;
    }

    currentHighlightedNotes = data.notes.map(note => toVisualizerNote(note));
    currentPlaybackNotes = data.notes;

    document.getElementById("result").textContent =
        `${chord.roman_numeral}: ${chord.symbol} = ${data.notes.join(", ")}`;

    currentExplanationContext =
    `Explain the ${chord.symbol} chord in this progression. It is the ${chord.roman_numeral} chord and contains the notes ${data.notes.join(", ")}. Explain its function for a beginner.`;
    refreshDiagram();
}

async function explainCurrentSelection() {
    const explanationBox = document.getElementById("aiExplanation");

    if (!currentExplanationContext) {
        explanationBox.textContent = "Generate a scale, chord, or progression first.";
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
        explanationBox.textContent = data.detail || "Something went wrong.";
        return;
    }

    explanationBox.textContent = data.response;
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
    const audioContext = new (window.AudioContext || window.webkitAudioContext)();

    notes.forEach((note, index) => {
        const oscillator = audioContext.createOscillator();
        const gainNode = audioContext.createGain();

        oscillator.type = "sine";
        oscillator.frequency.value = noteFrequencies[note];

        oscillator.connect(gainNode);
        gainNode.connect(audioContext.destination);

        const startTime = audioContext.currentTime + index * 0.45;
        const endTime = startTime + 0.4;

        gainNode.gain.setValueAtTime(0.2, startTime);
        gainNode.gain.exponentialRampToValueAtTime(0.001, endTime);

        oscillator.start(startTime);
        oscillator.stop(endTime);
    });
}

function playSingleNote(noteWithOctave) {
    const frequency = getNoteFrequency(noteWithOctave);

    if (!frequency) {
        console.log("No frequency found for:", noteWithOctave);
        return;
    }

    const audioContext = new (window.AudioContext || window.webkitAudioContext)();
    const oscillator = audioContext.createOscillator();
    const gainNode = audioContext.createGain();

    oscillator.type = "sine";
    oscillator.frequency.value = frequency;

    oscillator.connect(gainNode);
    gainNode.connect(audioContext.destination);

    const startTime = audioContext.currentTime;
    const endTime = startTime + 0.6;

    gainNode.gain.setValueAtTime(0.2, startTime);
    gainNode.gain.exponentialRampToValueAtTime(0.001, endTime);

    oscillator.start(startTime);
    oscillator.stop(endTime);
}

function playChord(notes) {
    const audioContext = new (window.AudioContext || window.webkitAudioContext)();

    notes.forEach(note => {
        const oscillator = audioContext.createOscillator();
        const gainNode = audioContext.createGain();

        oscillator.type = "sine";
        oscillator.frequency.value = noteFrequencies[note];

        oscillator.connect(gainNode);
        gainNode.connect(audioContext.destination);

        const startTime = audioContext.currentTime;
        const endTime = startTime + 1.2;

        gainNode.gain.setValueAtTime(0.15, startTime);
        gainNode.gain.exponentialRampToValueAtTime(0.001, endTime);

        oscillator.start(startTime);
        oscillator.stop(endTime);
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

        const response = await fetch(`${API_URL}/chords`, {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({
                root: chord.root,
                chord_type: chord.quality
            })
        });

        const data = await response.json();

        if (response.ok) {
            setTimeout(() => {
                playChord(data.notes);
            }, i * 1300);
        }
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