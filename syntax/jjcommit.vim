" Vim syntax file
" Language:	jj (Jujutsu) commit/describe message
" Maintainer:	NeoJJ

if exists("b:current_syntax")
  finish
endif

scriptencoding utf-8

syn case match
syn sync minlines=50
syn sync linebreaks=1

if has("spell")
  syn spell toplevel
endif

" Include diff syntax for inline diffs
syn include @jjcommitDiff syntax/diff.vim
syn region jjcommitDiff start=/\%(^diff --\%(git\|cc\|combined\) \)\@=/ end=/^\%(diff --\|$\|@@\@!\|[^[:alnum:]\ +-]\S\@!\)\@=/ fold contains=@jjcommitDiff

" First line is the summary (like git commit subject)
if get(g:, 'jjcommit_summary_length', 1) > 0
  exe 'syn match   jjcommitSummary	"^.*\%<' . (get(g:, 'jjcommit_summary_length', 72) + 1) . 'v." contained containedin=jjcommitFirstLine nextgroup=jjcommitOverflow contains=@Spell'
endif
syn match   jjcommitOverflow	".*" contained contains=@Spell
syn match   jjcommitBlank	"^.\+" contained contains=@Spell
syn match   jjcommitFirstLine	"\%^.*" nextgroup=jjcommitBlank,jjcommitComment skipnl

" JJ: comment lines
syn match   jjcommitComment	"^JJ:.*"

" Headers within comments: "Change ID:", "This commit contains..."
syn match   jjcommitHeader	"\%(^JJ: \)\@<=\S.*:$" contained containedin=jjcommitComment
syn match   jjcommitHeader	"\%(^JJ: \)\@<=Change ID:.*" contained containedin=jjcommitComment
syn match   jjcommitHeader	"\%(^JJ: \)\@<=This commit contains.*" contained containedin=jjcommitComment
syn match   jjcommitHeader	"\%(^JJ: \)\@<=Commands:$" contained containedin=jjcommitComment

" Change IDs and commit hashes in comments
syn match   jjcommitHash	"\<\x\{8,}\>" contains=@NoSpell display

" File status within comments (M, A, D, R prefixes)
syn match   jjcommitType	"\%(^JJ:\s\+\)\@<=[MADR]\ze " contained containedin=jjcommitComment nextgroup=jjcommitFile skipwhite
syn match   jjcommitFile	"\S.*" contained contains=@NoSpell

" Keybinding hints in Commands section
syn match   jjcommitKeybind	"<[^>]\+>" contained containedin=jjcommitComment

" Highlight links
hi def link jjcommitSummary		Keyword
hi def link jjcommitComment		Comment
hi def link jjcommitHash		Identifier
hi def link jjcommitHeader		PreProc
hi def link jjcommitType		Type
hi def link jjcommitFile		Constant
hi def link jjcommitOverflow		Error
hi def link jjcommitBlank		Error
hi def link jjcommitKeybind		Special

let b:current_syntax = "jjcommit"
