pragma ComponentBehavior: Bound

import QtQuick

// Readline-style single-line editing; result navigation belongs to the panel.
TextInput {
    id: input
    property string killedText: ""
    signal shortcut(var event)

    function isWord(character) {
        return !!character && !/[\s.,;:!?()[\]{}"'\/\\，。；：！？、（）【】「」『』-]/.test(character);
    }
    function wordBoundary(direction) {
        let position = cursorPosition;
        if (direction < 0) {
            while (position > 0 && !isWord(text[position - 1])) position--;
            while (position > 0 && isWord(text[position - 1])) position--;
        } else {
            while (position < text.length && !isWord(text[position])) position++;
            while (position < text.length && isWord(text[position])) position++;
        }
        return position;
    }
    function erase(start, end, remember) {
        if (start === end) return;
        if (remember) killedText = text.slice(start, end);
        remove(start, end);
        cursorPosition = start;
    }
    function eraseSelection(remember) {
        if (selectionStart === selectionEnd) return false;
        erase(selectionStart, selectionEnd, remember);
        return true;
    }
    function editKey(event) {
        const control = event.modifiers & Qt.ControlModifier;
        const alt = event.modifiers & Qt.AltModifier;
        if (control && !alt) {
            switch (event.key) {
            case Qt.Key_A: cursorPosition = 0; break;
            case Qt.Key_E: cursorPosition = text.length; break;
            case Qt.Key_F: cursorPosition = Math.min(text.length, cursorPosition + 1); break;
            case Qt.Key_B: cursorPosition = Math.max(0, cursorPosition - 1); break;
            case Qt.Key_H:
                if (!eraseSelection(false)) erase(Math.max(0, cursorPosition - 1), cursorPosition, false);
                break;
            case Qt.Key_D:
                if (!eraseSelection(false)) erase(cursorPosition, Math.min(text.length, cursorPosition + 1), false);
                break;
            case Qt.Key_K: erase(cursorPosition, text.length, true); break;
            case Qt.Key_U: erase(0, cursorPosition, true); break;
            case Qt.Key_W:
                if (!eraseSelection(true)) erase(wordBoundary(-1), cursorPosition, true);
                break;
            case Qt.Key_Y:
                if (!killedText) break;
                eraseSelection(false);
                const position = cursorPosition;
                insert(position, killedText);
                cursorPosition = position + killedText.length;
                break;
            default: return;
            }
        } else if (alt && !control) {
            switch (event.key) {
            case Qt.Key_B: cursorPosition = wordBoundary(-1); break;
            case Qt.Key_F: cursorPosition = wordBoundary(1); break;
            case Qt.Key_D: erase(cursorPosition, wordBoundary(1), true); break;
            case Qt.Key_Backspace: erase(wordBoundary(-1), cursorPosition, true); break;
            default: return;
            }
        } else return;
        event.accepted = true;
    }

    Keys.onPressed: event => {
        event.accepted = false;
        input.shortcut(event);
        if (!event.accepted) input.editKey(event);
    }
}
