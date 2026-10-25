#pragma once
#include <string>
#include <algorithm>
#include <cstdint>

// Result strings come from Windows, not from guessed Hangul syllable boundaries.
struct ImeCommitBuffer {
    std::u16string committed;
    std::u16string expected_native;
    std::u16string expected_ime_char;
    uint64_t result_count = 0;
    uint64_t suppressed_count = 0;
    void capture(const std::u16string &value) {
        if (value.empty()) return;
        committed += value;
        expected_native += value;
        expected_ime_char += value;
        ++result_count;
    }
    bool consume_duplicate(char16_t value, bool ime_message = false) {
        auto &expected = ime_message ? expected_ime_char : expected_native;
        if (!expected.empty() && expected.front() == value) {
            expected.erase(0, 1);
            ++suppressed_count;
            return true;
        }
        return false;
    }
    void capture_character(char16_t value, bool ime_message) {
        if (consume_duplicate(value, ime_message)) return;
        committed += value;
        // Some input methods emit either WM_CHAR or WM_IME_CHAR, or both.
        (ime_message ? expected_native : expected_ime_char) += value;
    }
    std::u16string take() {
        std::u16string value;
        value.swap(committed);
        // Native messages for this input batch have now been processed.
        expected_native.clear();
        expected_ime_char.clear();
        return value;
    }
    void clear() { committed.clear(); expected_native.clear(); expected_ime_char.clear(); }
};
