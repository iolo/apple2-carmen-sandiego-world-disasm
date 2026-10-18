# apple2-carmen-sandiego-world-korean

## GOAL

Korean translated version of the Apple II game "Where in the World is is Carmen Sandiego?".

## INPUT

- Original disk images(carmen-world.po), materials and disassembled source code, assests and documents.
- Target machine: 128K Apple //e

## OUTPUT

- Step1. Extract text to translate.
- Step2. Translate the extracted text into Korean.
- Step3. Request and confirm human review.
- Patch the original game with the translated Korean text.
- Target machine: 128K Apple //e

## Notes

- To simplify, no Korean Input Method.
- If available memory or disk space is insufficient for Korean support, stop and report the measured capacity and shortfall. Obtain the user's explicit confirmation of an alternative approach before proceeding.
- Do not translate any output displayed in Apple II TEXT MODE, including boot-loader messages. Keep those messages in English.
- If needed, define a custom game-text encoding to avoid conflicts with control bytes, string terminators, dictionary tokens, and glyph indexes; update the affected readers and renderers together.
- I remember the oringial(not cracked for PRODOS) game runs on 64K Apple II+. So, there're possible free memory for Korean support, I guess.
- You might use [GamuriMono7 Font](https://github.com/quiple/galmuri/) which has 7x8 pixels glyph(8bytes per glyph) like general Apple II fonts. You can ignore readability(character-spacing, line-scacing) of the font.
- You might extract used glyphs(english and hangul syllables) from the translated text, and create a custom font to reduce size.

## references

- my previous dissembly and korean translation project for Apple II game "The mask of the sun"
  - https://github.com/iolo/apple2-mask-of-sun-disasm
- and its korean translation project
  - https://github.com/iolo/apple2-mask-of-sun-disasm/tree/korean (korean branch)
  - already checked out in /home/iolo/workspace/retro/apple2-mask-of-sun-korean
