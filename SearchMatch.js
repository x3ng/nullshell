.pragma library

// Exact names and literal keywords always outrank abbreviated name matches.
function literal(text, needle) {
    const value = String(text || "").toLocaleLowerCase();
    if (!needle || value === needle) return 0;
    if (value.startsWith(needle)) return 10;
    const terms = needle.split(/\s+/).filter(Boolean);
    let score = 0;
    for (const term of terms) {
        const index = value.indexOf(term);
        if (index < 0) return 1000;
        score += index === 0 ? 10 : /[\s\-_./]/.test(value[index - 1]) ? 20 : 30;
    }
    return score / terms.length;
}

function score(name, metadata, needle) {
    needle = String(needle || "").trim().toLocaleLowerCase();
    const direct = literal(name, needle);
    if (direct < 1000) return direct;
    const keyword = literal(metadata, needle);
    if (keyword < 1000) return 100 + keyword;
    // Deliberately conservative: one ASCII abbreviation, bounded name length
    // and gaps. No fuzzy matching across comments or arbitrary command text.
    if (!/^[a-z0-9]{2,32}$/.test(needle)) return 1000;
    const value = String(name || "").toLocaleLowerCase().slice(0, 256);
    const initials = value.split(/[^a-z0-9]+/).filter(Boolean).map(word => word[0]).join("");
    if (initials.startsWith(needle)) return 200 + initials.length - needle.length;
    let position = -1;
    let first = -1;
    for (const character of needle) {
        position = value.indexOf(character, position + 1);
        if (position < 0) return 1000;
        if (first < 0) first = position;
    }
    const span = position - first + 1;
    return span <= needle.length * 4 ? 220 + span - needle.length + first : 1000;
}
