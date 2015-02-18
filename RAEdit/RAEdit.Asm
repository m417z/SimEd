comment *
	KetilO (C) 2002 - 2009
	radasmide@hotmail.com
*

.386

.model flat, stdcall
option casemap :none   ; case sensitive
option proc:private

include windows.inc
include comctl32.inc
include user32.inc
include kernel32.inc
include gdi32.inc
include ole32.inc

includelib comctl32.lib
includelib user32.lib
includelib kernel32.lib
includelib gdi32.lib
includelib ole32.lib

include masm32.inc
include Debug.Inc
includelib masm32.lib
includelib Debug.lib

include ..\RAEdit.inc
include Data.inc
include Misc.asm
include Position.asm
include Paint.asm
include Memory.asm
include Edit.asm
include Function.asm
include Block.asm
include Undo.asm
include ClipBoard.asm
include DragDrop.asm

.code

TimerProc proc hWin:DWORD,uMsg:DWORD,idEvent:DWORD,dwTime:DWORD

	.if tmr1.hwnd
			invoke PostMessage,tmr1.hwnd,tmr1.umsg,tmr1.wparam,tmr1.lparam
			mov		tmr1.hwnd,0
	.endif
	.if tmr2.hwnd
		invoke PostMessage,tmr2.hwnd,tmr2.umsg,tmr2.wparam,tmr2.lparam
		mov		tmr2.hwnd,0
	.endif
	invoke KillTimer,NULL,TimerID
	ret

TimerProc endp

;Create a windowclass for the user control
InstallRAEdit proc public hInst:HINSTANCE,fGlobal:DWORD
	LOCAL	wc:WNDCLASSEX
	LOCAL	hBmp:DWORD

	push    hInst
	pop     hInstance
	mov		wc.cbSize,sizeof WNDCLASSEX
	mov		wc.style,CS_HREDRAW or CS_VREDRAW
	.if fGlobal
		mov		wc.style,CS_HREDRAW or CS_VREDRAW or CS_GLOBALCLASS
	.endif
	mov		wc.lpfnWndProc,offset RAWndProc
	mov		wc.cbClsExtra,NULL
	mov		wc.cbWndExtra,4		;Holds memory handle
	push	hInst
	pop		wc.hInstance
	mov		wc.hbrBackground,NULL
	mov		wc.lpszMenuName,NULL
	mov		wc.lpszClassName,offset szRAEditClass
	mov		eax,NULL
	mov		wc.hIcon,eax
	mov		wc.hIconSm,eax
	invoke LoadCursor,NULL,IDC_ARROW
	mov		wc.hCursor,eax
	invoke RegisterClassEx,addr wc

	mov		wc.cbSize,sizeof WNDCLASSEX
	mov		wc.style,CS_DBLCLKS or CS_HREDRAW or CS_VREDRAW
	mov		wc.lpfnWndProc,offset RAEditProc
	mov		wc.cbClsExtra,NULL
	mov		wc.cbWndExtra,4		;Holds memory handle
	push	hInst
	pop		wc.hInstance
	mov		wc.hbrBackground,NULL
	mov		wc.lpszMenuName,NULL
	mov		wc.lpszClassName,offset szEditClassName
	mov		eax,NULL
	mov		wc.hIcon,eax
	mov		wc.hIconSm,eax
	invoke LoadCursor,NULL,IDC_IBEAM
	mov		wc.hCursor,eax
	invoke RegisterClassEx,addr wc
	invoke LoadCursor,hInst,IDC_HSPLITTCUR
	mov		hHSCur,eax
	invoke LoadCursor,hInstance,IDC_SELECTCUR
	mov		hSelCur,eax
	invoke LoadBitmap,hInstance,IDB_BOOKMARK
	mov		hBmp,eax
	invoke ImageList_Create,11,11,ILC_COLOR4 or ILC_MASK,7,7
	mov		hIml,eax
	invoke ImageList_AddMasked,hIml,hBmp,0C0C0C0h
	invoke DeleteObject,hBmp
	invoke LoadBitmap,hInstance,IDB_LINENUMBER
	mov		hBmpLnr,eax
	invoke LoadBitmap,hInstance,IDB_EXPAND
	mov		hBmpExp,eax
	invoke LoadBitmap,hInstance,IDB_COLLAPSE
	mov		hBmpCol,eax
	invoke LoadBitmap,hInstance,IDB_LOCK
	mov		hBmpLck,eax
	invoke GetSysColor,COLOR_INFOBK
	invoke CreateSolidBrush,eax
	mov		hBrTlt,eax
	;Allocate memory for the word list
	invoke GetProcessHeap
	invoke xHeapAlloc,eax,HEAP_ZERO_MEMORY,MAXWORDMEM
	mov		hWrdMem,eax
	mov		cbWrdMem,MAXWORDMEM
	mov		rpWrdFree,256*4
	;Setup upper CharTab
	push	ebx
	mov		ebx,128
	.while ebx<256
		invoke IsCharAlphaNumeric,ebx
		mov		CharTab[ebx],al
		inc		ebx
	.endw
	;Setup whole CaseTab
	xor		ebx,ebx
	.while ebx<256
		invoke IsCharAlpha,ebx
		.if eax
			invoke CharUpper,ebx
			.if eax==ebx
				invoke CharLower,ebx
			.endif
			mov		CaseTab[ebx],al
		.else
			mov		CaseTab[ebx],bl
		.endif
		inc		ebx
	.endw
	pop		ebx
	ret

InstallRAEdit endp

UnInstallRAEdit proc public

	invoke DestroyCursor,hHSCur
	invoke DestroyCursor,hSelCur
	invoke ImageList_Destroy,hIml
	invoke DeleteObject,hBmpLnr
	invoke DeleteObject,hBmpCol
	invoke DeleteObject,hBmpExp
	invoke DeleteObject,hBmpLck
	invoke DeleteObject,hBrTlt
	invoke GetProcessHeap
	invoke HeapFree,eax,0,hWrdMem
	ret

UnInstallRAEdit endp

;Prefix ^		Word is case sensitive
;Prefix ~		Word is case converted
;Suffix +		Hilites rest of line with comment color
;Suffix -		Hilites rest of line with text color
;
;nColor			gggg0sff cccccccc cccccccc cccccccc
;				g=Word group, s=Case sensitive, f=Font style, c=color
SetHiliteWords proc public uses esi edi,nColor:DWORD,lpWords:DWORD
	LOCAL	fEnd:DWORD
	LOCAL	fEnd2:DWORD
	LOCAL	len:DWORD

	mov		esi,lpWords
	.if !esi
		mov		edi,hWrdMem
		mov		ecx,cbWrdMem
		shr		ecx,2
		xor		eax,eax
		rep stosd
		mov		rpWrdFree,256*4
	.else
	  NxtWrd:
		mov		fEnd,0
		.if byte ptr nColor[3] & 4 
			; group is case sensitive. Toggles meaning of '^'
			or		fEnd,3
		.endif
  		invoke ExpandWordMem
		mov		edi,hWrdMem
	  NxtWrd1:
		movzx	eax,byte ptr [esi]
		.if eax
			.if eax==' ' || eax==VK_TAB || eax==VK_RETURN || eax==0Ah
				inc		esi
				jmp		NxtWrd
			.endif
			.if al>='a' && al<='z'
				and		al,5Fh
			.elseif al=='^'
				xor		fEnd,3
				inc		esi
				jmp		NxtWrd1
			.elseif al=='~'
				mov		fEnd,4
				inc		esi
				jmp		NxtWrd1
			.endif
			push	eax
			call	NestedProc_TestWord
			mov		ecx,eax
			pop		eax
			.if ecx!=0
				jmp		NxtWrd
			.endif
			;pointer to previous
			mov		edx,[edi+eax*4]
			;pointer to free
			mov		ecx,rpWrdFree
			mov		[edi+eax*4],ecx
		  NxtChar:
			mov		al,[esi]
			inc		esi
			.if al==' ' || al==VK_TAB || al==VK_RETURN || al==0Ah || !al
				.if !al
					dec		esi
				.endif
				mov		byte ptr [edi+ecx+sizeof WORDINFO],0
				mov		eax,ecx
				mov		ecx,rpWrdFree
				sub		eax,ecx
				mov		[edi+ecx].WORDINFO.len,eax
				add		eax,sizeof WORDINFO+1
				add		rpWrdFree,eax
				mov		[edi+ecx].WORDINFO.rpprev,edx
				mov		eax,nColor
				mov		[edi+ecx].WORDINFO.color,eax
				mov		eax,fEnd
				mov		[edi+ecx].WORDINFO.fend,eax
				jmp		NxtWrd
			.endif
			.if al=='-'
				or		fEnd,1
			.elseif al=='+'
				or		fEnd,2
			.else
				mov		[edi+ecx+sizeof WORDINFO],al
				inc		ecx
			.endif
			jmp		NxtChar
		.endif
	.endif
	ret

NestedProc_GetLen:
	xor		ecx,ecx
  @@:
	mov		al,[esi+ecx]
	.if al>' '
		inc		ecx
		jmp		@b
	.endif
	mov		len,ecx
	retn

NestedProc_TestWord:
	push	edi
	call	NestedProc_GetLen
	movzx	eax,byte ptr [esi]
	.if eax>='a' && eax<='z' && fEnd!=3
		and		eax,5Fh
	.endif
	mov		edi,hWrdMem
	mov		edx,[edi+eax*4]
	xor		eax,eax
	.if edx==0
		jmp		Ex
	.endif
  @@:
	mov		eax,[edi+edx].WORDINFO.fend
	mov		fEnd2,eax
	mov		eax,[edi+edx].WORDINFO.color
	shr		eax,28
	mov		ecx,nColor
	shr		ecx,28
	.if eax!=ecx
		mov		edx,[edi+edx].WORDINFO.rpprev
		.if edx
			jmp		@b
		.else
			xor		eax,eax
			jmp		Ex
		.endif
	.endif
	mov		eax,[edi+edx].WORDINFO.len
	mov		ecx,len
	.if eax!=ecx
		mov		edx,[edi+edx].WORDINFO.rpprev
		.if edx
			jmp		@b
		.else
			xor		eax,eax
			jmp		Ex
		.endif
	.endif
	push	edx
	mov		ecx,len
	lea		edx,[edi+edx+sizeof WORDINFO]
	xor		eax,eax
	.while ecx && !eax
		dec		ecx
		mov		al,[esi+ecx]
		mov		ah,[edx+ecx]
		.if fEnd!=3
			.if al>='a' && al<='z'
				and		al,5fh
			.endif
		.endif
		.if fEnd2!=3
			.if ah>='a' && ah<='z'
				and		ah,5fh
			.endif
		.endif
		sub		al,ah
		xor		ah,ah
	.endw
	pop		edx
	.if !eax
		inc		eax
		add		esi,len
		jmp		Ex
	.endif
	mov		edx,[edi+edx].WORDINFO.rpprev
	.if edx
		jmp		@b
	.else
		xor		eax,eax
		jmp		Ex
	.endif
  Ex:
	pop		edi
	retn

SetHiliteWords endp

GetCharTabPtr proc public

	mov		eax,offset CharTab
	ret

GetCharTabPtr endp

GetCharTabVal proc public nChar:DWORD

	mov		edx,nChar
	and		edx,0FFh
	movzx	eax,byte ptr [edx+offset CharTab]
	ret

GetCharTabVal endp

SetCharTabVal proc public nChar:DWORD,nValue:DWORD

	mov		edx,nChar
	and		edx,0FFh
	mov		eax,nValue
	mov		byte ptr [edx+offset CharTab],al
	ret

SetCharTabVal endp

SetBlockDef proc public uses ebx esi edi,lpRABLOCKDEF:DWORD

	.if !lpRABLOCKDEF
		mov		ecx,sizeof blockdefs/4
		mov		edi,offset blockdefs
		xor		eax,eax
		rep stosd
	.else
		mov		ebx,lpRABLOCKDEF
		mov		esi,offset blockdefs
		lea		edi,[esi+32*4]
		.while dword ptr [esi]
			invoke IsBlockDefEqual,ebx,edi
			.if eax
				jmp		Ex
			.endif
			mov		edi,dword ptr [esi]
			add		esi,4
		.endw
		lea		ecx,[edi+sizeof RABLOCKDEF]
		mov		eax,[ebx].RABLOCKDEF.flag
		mov		[edi].RABLOCKDEF.flag,eax
		mov		eax,[ebx].RABLOCKDEF.lpszStart
		.if eax
			mov		[edi].RABLOCKDEF.lpszStart,ecx
			push	ecx
			push	eax
			invoke lstrcpy,ecx,eax
			pop		eax
			invoke strlen,eax
			pop		ecx

			call	NestedProc_TestString
			inc		eax
			mov		byte ptr [ecx+eax],0

			lea		ecx,[ecx+eax+1]
		.endif
		mov		eax,[ebx].RABLOCKDEF.lpszEnd
		.if eax
			mov		[edi].RABLOCKDEF.lpszEnd,ecx
			push	ecx
			push	eax
			invoke lstrcpy,ecx,eax
			pop		eax
			invoke strlen,eax
			pop		ecx
			call	NestedProc_TestString
			inc		eax
			mov		byte ptr [ecx+eax],0
			lea		ecx,[ecx+eax+1]
		.endif
		mov		eax,[ebx].RABLOCKDEF.lpszNot1
		.if eax
			mov		[edi].RABLOCKDEF.lpszNot1,ecx
			push	ecx
			push	eax
			invoke lstrcpy,ecx,eax
			pop		eax
			invoke strlen,eax
			pop		ecx
			lea		ecx,[ecx+eax+1]
		.endif
		mov		eax,[ebx].RABLOCKDEF.lpszNot2
		.if eax
			mov		[edi].RABLOCKDEF.lpszNot2,ecx
			push	ecx
			push	eax
			invoke lstrcpy,ecx,eax
			pop		eax
			invoke strlen,eax
			pop		ecx
			lea		ecx,[ecx+eax+1]
		.endif
		mov		dword ptr [esi],ecx
	.endif
  Ex:
	ret

NestedProc_TestString:
	push	ecx
	.while byte ptr [ecx]
		.if byte ptr [ecx]=='|'
			mov		byte ptr [ecx],0
		.endif
		inc		ecx
	.endw
	pop		ecx
	retn

SetBlockDef endp

;--------------------------------------------------------------------------------

SplittBtnProc proc uses ebx,hWin:HWND,uMsg:UINT,wParam:WPARAM,lParam:LPARAM

	mov		eax,uMsg
	.if eax==WM_MOUSEMOVE
		invoke GetParent,hWin
		invoke GetWindowLong,eax,0
		mov		ebx,eax
		invoke SetCursor,hHSCur
	.elseif eax==WM_LBUTTONDOWN
		invoke GetParent,hWin
		invoke GetWindowLong,eax,0
		mov		ebx,eax
		mov		[ebx].EDIT.fresize,1
		invoke SetCapture,[ebx].EDIT.hwnd
		invoke SetCursor,hHSCur
	.elseif eax==WM_LBUTTONDBLCLK
		invoke GetParent,hWin
		push	eax
		invoke GetWindowLong,eax,0
		mov		ebx,eax
		mov		eax,511
		.if [ebx].EDIT.fsplitt
			mov		eax,0
		.endif
		pop		edx
		invoke SendMessage,edx,REM_SETSPLIT,eax,0
		xor		eax,eax
		ret
	.endif
	invoke CallWindowProc,OldSplittBtnProc,hWin,uMsg,wParam,lParam
	ret

SplittBtnProc endp

StateProc proc uses ebx,hWin:HWND,uMsg:UINT,wParam:WPARAM,lParam:LPARAM
	LOCAL	ps:PAINTSTRUCT
	LOCAL	hBr:DWORD

	.if uMsg==WM_PAINT
		invoke BeginPaint,hWin,addr ps
		invoke GetWindowLong,hWin,GWL_USERDATA
		mov		ebx,eax
		.if [ebx].EDIT.fstyle&STYLE_READONLY
			invoke CreateSolidBrush,0FFh
			mov		hBr,eax
		.elseif [ebx].EDIT.fChanged
			invoke CreateSolidBrush,0B000h
			mov		hBr,eax
		.else
			mov		hBr,0
			mov		eax,[ebx].EDIT.br.hBrSelBar
		.endif
		invoke FillRect,ps.hdc,addr ps.rcPaint,eax
		.if hBr
			invoke DeleteObject,hBr
		.endif
		invoke EndPaint,hWin,addr ps
		xor		eax,eax
		ret
	.endif
	invoke CallWindowProc,OldStateProc,hWin,uMsg,wParam,lParam
	ret

StateProc endp

EditFunc proc  uses ebx esi edi,hWin:HWND,uMsg:UINT,fAlt:DWORD,fShift:DWORD,fControl:DWORD
	LOCAL	pt:POINT
	LOCAL	cpOldMin:DWORD
	LOCAL	cpOldMax:DWORD
	LOCAL	oldrects[2]:RECT
	LOCAL	nOldLine:DWORD
	LOCAL	fSel:DWORD

	invoke GetWindowLong,hWin,0
	mov		ebx,eax
	mov		eax,hWin
	.if eax==[ebx].EDIT.edta.hwnd
		lea		esi,[ebx].EDIT.edta
	.else
		lea		esi,[ebx].EDIT.edtb
	.endif
	mov		eax,[ebx].EDIT.cpMin
	mov		cpOldMin,eax
	mov		edx,[ebx].EDIT.cpMax
	mov		cpOldMax,edx
	sub		edx,eax
	mov		fSel,edx
	mov		eax,uMsg
	movzx	eax,ax
	.if eax==CMD_LINE_UP
		.if fAlt
			.if fControl && !fShift
				;Up, size split
				.if [ebx].EDIT.fsplitt
					.if [ebx].EDIT.fsplitt>10
						sub		[ebx].EDIT.fsplitt,10
					.else
						mov		[ebx].EDIT.fsplitt,0
					.endif
					invoke SendMessage,[ebx].EDIT.hwnd,WM_SIZE,0,0
					invoke UpdateWindow,[ebx].EDIT.edta.hwnd
					invoke UpdateWindow,[ebx].EDIT.edtb.hwnd
					invoke UpdateWindow,[ebx].EDIT.hsbtn
				.endif
			.endif
		.else
			.if fControl
				invoke SendMessage,hWin,WM_VSCROLL,SB_LINEUP,[esi].RAEDT.hvscroll
			.else
				.if !([ebx].EDIT.nMode&MODE_BLOCK)
					mov		eax,[ebx].EDIT.cpMin
					.if eax>[ebx].EDIT.cpMax && !fShift
						xchg	eax,[ebx].EDIT.cpMax
						mov		[ebx].EDIT.cpMin,eax
						invoke SetCaret,ebx,[esi].RAEDT.cpy
					.endif
					push	[ebx].EDIT.cpx
					invoke GetCaretPos,addr pt
					mov		eax,[ebx].EDIT.fntinfo.fntht
					sub		pt.y,eax
					mov		eax,[esi].RAEDT.cpxmax
					add		eax,[ebx].EDIT.selbarwt
					add		eax,[ebx].EDIT.linenrwt
					sub		eax,[ebx].EDIT.cpx
					invoke GetCharFromPos,ebx,[esi].RAEDT.cpy,eax,pt.y
					.if eax!=[ebx].EDIT.cpLine
						push	eax
						dec		eax
						invoke IsCharLeadByte,ebx,eax
						pop		edx
						add		eax,edx
					.endif
					mov		[ebx].EDIT.cpMin,eax
					.if !fShift
						mov		[ebx].EDIT.cpMax,eax
					.endif
					pop		[ebx].EDIT.cpx
					invoke SetCaretVisible,hWin,[esi].RAEDT.cpy
					invoke SetCaret,ebx,[esi].RAEDT.cpy
					.if !fShift && fSel
						invoke InvalidateEdit,ebx,[ebx].EDIT.edta.hwnd
						invoke InvalidateEdit,ebx,[ebx].EDIT.edtb.hwnd
					.elseif fShift
						invoke InvalidateLine,ebx,[ebx].EDIT.edta.hwnd,[ebx].EDIT.line
						invoke InvalidateLine,ebx,[ebx].EDIT.edtb.hwnd,[ebx].EDIT.line
						push	[ebx].EDIT.line
						invoke GetCharPtr,ebx,cpOldMin
						pop		eax
						.if eax!=[ebx].EDIT.line
							invoke InvalidateLine,ebx,[ebx].EDIT.edta.hwnd,[ebx].EDIT.line
							invoke InvalidateLine,ebx,[ebx].EDIT.edtb.hwnd,[ebx].EDIT.line
						.endif
						invoke UpdateWindow,[ebx].EDIT.edta.hwnd
						invoke UpdateWindow,[ebx].EDIT.edtb.hwnd
					.endif
				.else
					invoke GetBlockRects,ebx,addr oldrects
					invoke GetCaretPos,addr pt
					mov		eax,pt.y
					sub		eax,[ebx].EDIT.fntinfo.fntht
					invoke GetCharFromPos,ebx,[esi].RAEDT.cpy,pt.x,eax
					mov		[ebx].EDIT.cpMin,eax
					mov		[ebx].EDIT.cpMax,eax
					mov		eax,pt.x
					add		eax,[ebx].EDIT.cpx
					sub		eax,[ebx].EDIT.linenrwt
					sub		eax,[ebx].EDIT.selbarwt
					mov		ecx,[ebx].EDIT.fntinfo.fntwt
					xor		edx,edx
					div		ecx
					mov		edx,[ebx].EDIT.line
					mov		[ebx].EDIT.blrg.lnMin,edx
					mov		[ebx].EDIT.blrg.clMin,eax
					.if !fShift
						mov		[ebx].EDIT.blrg.lnMax,edx
						mov		[ebx].EDIT.blrg.clMax,eax
					.endif
					invoke InvalidateBlock,ebx,addr oldrects
					invoke SetCaretVisible,hWin,[esi].RAEDT.cpy
					invoke SetCaret,ebx,[esi].RAEDT.cpy
				.endif
				invoke SelChange,ebx,SEL_TEXT
				inc		nUndoid
			.endif
		.endif
	.elseif eax==CMD_LINE_DOWN
		.if fAlt
			.if fControl && !fShift
				;Down, size split
				.if [ebx].EDIT.fsplitt<960
					add		[ebx].EDIT.fsplitt,10
					.if [ebx].EDIT.fsplitt>960
						mov		[ebx].EDIT.fsplitt,960
					.endif
					invoke SendMessage,[ebx].EDIT.hwnd,WM_SIZE,0,0
					invoke UpdateWindow,[ebx].EDIT.edta.hwnd
					invoke UpdateWindow,[ebx].EDIT.edtb.hwnd
					invoke UpdateWindow,[ebx].EDIT.hsbtn
				.endif
			.endif
		.else
			.if fControl
				invoke SendMessage,hWin,WM_VSCROLL,SB_LINEDOWN,[esi].RAEDT.hvscroll
			.else
				.if !([ebx].EDIT.nMode&MODE_BLOCK)
					invoke GetCharPtr,ebx,[ebx].EDIT.cpMin
					mov		nOldLine,edx
					mov		eax,[ebx].EDIT.cpMin
					.if eax<[ebx].EDIT.cpMax && !fShift
						xchg	eax,[ebx].EDIT.cpMax
						mov		[ebx].EDIT.cpMin,eax
						invoke SetCaret,ebx,[esi].RAEDT.cpy
					.endif
					push	[ebx].EDIT.cpx
					invoke GetCaretPos,addr pt
					mov		eax,[ebx].EDIT.fntinfo.fntht
					add		pt.y,eax
					mov		eax,[esi].RAEDT.cpxmax
					add		eax,[ebx].EDIT.selbarwt
					add		eax,[ebx].EDIT.linenrwt
					sub		eax,[ebx].EDIT.cpx
					invoke GetCharFromPos,ebx,[esi].RAEDT.cpy,eax,pt.y
					push	eax
					.if eax
						dec		eax
						invoke IsCharLeadByte,ebx,eax
					.endif
					pop		edx
					add		edx,eax
					mov		eax,edx
					mov		[ebx].EDIT.cpMin,eax
					.if !fShift
						mov		[ebx].EDIT.cpMax,eax
					.endif
					pop		[ebx].EDIT.cpx
					invoke SetCaretVisible,hWin,[esi].RAEDT.cpy
					invoke SetCaret,ebx,[esi].RAEDT.cpy
					.if !fShift && fSel
						invoke InvalidateEdit,ebx,[ebx].EDIT.edta.hwnd
						invoke InvalidateEdit,ebx,[ebx].EDIT.edtb.hwnd
					.elseif fShift
						invoke InvalidateLine,ebx,[ebx].EDIT.edta.hwnd,[ebx].EDIT.line
						invoke InvalidateLine,ebx,[ebx].EDIT.edtb.hwnd,[ebx].EDIT.line
						mov		eax,nOldLine
						.if eax!=[ebx].EDIT.line
							invoke InvalidateLine,ebx,[ebx].EDIT.edta.hwnd,nOldLine
							invoke InvalidateLine,ebx,[ebx].EDIT.edtb.hwnd,nOldLine
						.endif
						invoke UpdateWindow,[ebx].EDIT.edta.hwnd
						invoke UpdateWindow,[ebx].EDIT.edtb.hwnd
					.endif
				.else
					invoke GetBlockRects,ebx,addr oldrects
					invoke GetCaretPos,addr pt
					mov		eax,pt.y
					add		eax,[ebx].EDIT.fntinfo.fntht
					invoke GetCharFromPos,ebx,[esi].RAEDT.cpy,pt.x,eax
					mov		[ebx].EDIT.cpMin,eax
					mov		[ebx].EDIT.cpMax,eax
					mov		eax,pt.x
					add		eax,[ebx].EDIT.cpx
					sub		eax,[ebx].EDIT.linenrwt
					sub		eax,[ebx].EDIT.selbarwt
					mov		ecx,[ebx].EDIT.fntinfo.fntwt
					xor		edx,edx
					div		ecx
					mov		edx,[ebx].EDIT.line
					mov		[ebx].EDIT.blrg.lnMin,edx
					mov		[ebx].EDIT.blrg.clMin,eax
					.if !fShift
						mov		[ebx].EDIT.blrg.lnMax,edx
						mov		[ebx].EDIT.blrg.clMax,eax
					.endif
					invoke InvalidateBlock,ebx,addr oldrects
					invoke SetCaretVisible,hWin,[esi].RAEDT.cpy
					invoke SetCaret,ebx,[esi].RAEDT.cpy
				.endif
				invoke SelChange,ebx,SEL_TEXT
				inc		nUndoid
			.endif
		.endif
	.elseif eax==CMD_LEFT
		.if fAlt
			.if fControl && !fShift
				;Left
				.if [ebx].EDIT.cpx>20
					sub		[ebx].EDIT.cpx,20
				.else
					mov		[ebx].EDIT.cpx,0
				.endif
				invoke InvalidateEdit,ebx,[ebx].EDIT.edta.hwnd
				invoke InvalidateEdit,ebx,[ebx].EDIT.edtb.hwnd
				invoke SetCaret,ebx,[esi].RAEDT.cpy
			.endif
		.else
			.if !([ebx].EDIT.nMode&MODE_BLOCK)
			  @@:
				mov		eax,[ebx].EDIT.cpMin
				.if eax>[ebx].EDIT.cpMax && !fShift
					mov		eax,[ebx].EDIT.cpMax
				.elseif eax>=[ebx].EDIT.cpMax || fShift
					.if eax
						.if eax>=2
							push	eax
							sub		eax,2
							invoke IsCharLeadByte,ebx,eax
							pop		edx
							sub		edx,eax
							mov		eax,edx
						.endif
						dec		eax
					.endif
				.endif
				.if fControl
					invoke SkipWhiteSpace,ebx,eax,TRUE
					invoke GetWordStart,ebx,eax,0
				.endif
				invoke GetCharPtr,ebx,eax
				mov		[ebx].EDIT.cpMin,ecx
				.if !fShift
					mov		[ebx].EDIT.cpMax,ecx
				.endif
				invoke IsLineHidden,ebx,edx
				.if eax!=0
					jmp		@b
				.endif
				invoke SetCaretVisible,hWin,[esi].RAEDT.cpy
				invoke SetCaret,ebx,[esi].RAEDT.cpy
				.if !fShift && fSel
					invoke InvalidateEdit,ebx,[ebx].EDIT.edta.hwnd
					invoke InvalidateEdit,ebx,[ebx].EDIT.edtb.hwnd
				.elseif fShift
					invoke InvalidateLine,ebx,[ebx].EDIT.edta.hwnd,[ebx].EDIT.line
					invoke InvalidateLine,ebx,[ebx].EDIT.edtb.hwnd,[ebx].EDIT.line
					push	[ebx].EDIT.line
					invoke GetCharPtr,ebx,cpOldMin
					pop		eax
					.if eax!=[ebx].EDIT.line
						invoke InvalidateLine,ebx,[ebx].EDIT.edta.hwnd,[ebx].EDIT.line
						invoke InvalidateLine,ebx,[ebx].EDIT.edtb.hwnd,[ebx].EDIT.line
					.endif
					invoke UpdateWindow,[ebx].EDIT.edta.hwnd
					invoke UpdateWindow,[ebx].EDIT.edtb.hwnd
				.endif
			.else
				invoke GetBlockRects,ebx,addr oldrects
				invoke GetCaretPos,addr pt
				mov		eax,pt.x
				sub		eax,[ebx].EDIT.fntinfo.fntwt
				invoke GetCharFromPos,ebx,[esi].RAEDT.cpy,eax,pt.y
				mov		[ebx].EDIT.cpMin,eax
				mov		[ebx].EDIT.cpMax,eax
				mov		eax,pt.x
				sub		eax,[ebx].EDIT.fntinfo.fntwt
				add		eax,[ebx].EDIT.cpx
				sub		eax,[ebx].EDIT.linenrwt
				sub		eax,[ebx].EDIT.selbarwt
				mov		ecx,[ebx].EDIT.fntinfo.fntwt
				cdq
				idiv		ecx
				.if sdword ptr eax<0
					xor		eax,eax
				.endif
				mov		edx,[ebx].EDIT.line
				mov		[ebx].EDIT.blrg.lnMin,edx
				mov		[ebx].EDIT.blrg.clMin,eax
				.if !fShift
					mov		[ebx].EDIT.blrg.lnMax,edx
					mov		[ebx].EDIT.blrg.clMax,eax
				.endif
				invoke InvalidateBlock,ebx,addr oldrects
				invoke SetCaretVisible,hWin,[esi].RAEDT.cpy
				invoke SetCaret,ebx,[esi].RAEDT.cpy
			.endif
			invoke SetCpxMax,ebx,hWin
			invoke SelChange,ebx,SEL_TEXT
			inc		nUndoid
		.endif
	.elseif eax==CMD_RIGHT
		.if fAlt
			.if fControl && !fShift
				;Right
				add		[ebx].EDIT.cpx,20
				invoke InvalidateEdit,ebx,[ebx].EDIT.edta.hwnd
				invoke InvalidateEdit,ebx,[ebx].EDIT.edtb.hwnd
				invoke SetCaret,ebx,[esi].RAEDT.cpy
			.endif
		.else
			.if !([ebx].EDIT.nMode&MODE_BLOCK)
			  @@:
				mov		eax,[ebx].EDIT.cpMin
				.if eax<[ebx].EDIT.cpMax && !fShift
					mov		eax,[ebx].EDIT.cpMax
				.elseif eax<=[ebx].EDIT.cpMax || fShift
					push	eax
					invoke IsCharLeadByte,ebx,eax
					pop		edx
					inc		edx
					add		edx,eax
					mov		eax,edx
				.endif
				.if fControl
					invoke SkipWhiteSpace,ebx,eax,FALSE
					invoke GetWordEnd,ebx,eax,0
				.endif
				invoke GetCharPtr,ebx,eax
				mov		eax,[ebx].EDIT.cpMin
				mov		[ebx].EDIT.cpMin,ecx
				.if !fShift
					mov		[ebx].EDIT.cpMax,ecx
				.endif
				mov		eax,edx
				inc		eax
				shl		eax,2
				.if eax<[ebx].EDIT.rpLineFree
					invoke IsLineHidden,ebx,edx
					.if eax!=0
						jmp		@b
					.endif
				.endif
				invoke SetCaretVisible,hWin,[esi].RAEDT.cpy
				invoke SetCaret,ebx,[esi].RAEDT.cpy
				.if !fShift && fSel
					invoke InvalidateEdit,ebx,[ebx].EDIT.edta.hwnd
					invoke InvalidateEdit,ebx,[ebx].EDIT.edtb.hwnd
				.elseif fShift
					invoke InvalidateLine,ebx,[ebx].EDIT.edta.hwnd,[ebx].EDIT.line
					invoke InvalidateLine,ebx,[ebx].EDIT.edtb.hwnd,[ebx].EDIT.line
					push	[ebx].EDIT.line
					invoke GetCharPtr,ebx,cpOldMin
					pop		eax
					.if eax!=[ebx].EDIT.line
						invoke InvalidateLine,ebx,[ebx].EDIT.edta.hwnd,[ebx].EDIT.line
						invoke InvalidateLine,ebx,[ebx].EDIT.edtb.hwnd,[ebx].EDIT.line
					.endif
					invoke UpdateWindow,[ebx].EDIT.edta.hwnd
					invoke UpdateWindow,[ebx].EDIT.edtb.hwnd
				.endif
			.else
				invoke GetBlockRects,ebx,addr oldrects
				invoke GetCaretPos,addr pt
				mov		eax,pt.x
				add		eax,[ebx].EDIT.fntinfo.fntwt
				invoke GetCharFromPos,ebx,[esi].RAEDT.cpy,eax,pt.y
				mov		[ebx].EDIT.cpMin,eax
				mov		[ebx].EDIT.cpMax,eax
				mov		eax,pt.x
				add		eax,[ebx].EDIT.fntinfo.fntwt
				add		eax,[ebx].EDIT.cpx
				sub		eax,[ebx].EDIT.linenrwt
				sub		eax,[ebx].EDIT.selbarwt
				mov		ecx,[ebx].EDIT.fntinfo.fntwt
				cdq
				idiv		ecx
				.if sdword ptr eax<0
					xor		eax,eax
				.endif
				mov		edx,[ebx].EDIT.line
				mov		[ebx].EDIT.blrg.lnMin,edx
				mov		[ebx].EDIT.blrg.clMin,eax
				.if !fShift
					mov		[ebx].EDIT.blrg.lnMax,edx
					mov		[ebx].EDIT.blrg.clMax,eax
				.endif
				invoke InvalidateBlock,ebx,addr oldrects
				invoke SetCaretVisible,hWin,[esi].RAEDT.cpy
				invoke SetCaret,ebx,[esi].RAEDT.cpy
			.endif
			invoke SetCpxMax,ebx,hWin
			invoke SelChange,ebx,SEL_TEXT
			inc		nUndoid
		.endif
	.elseif eax==CMD_PAGE_UP
		.if fAlt
			.if fControl && !fShift
				;PgUp, collapse
				mov		ax,-4
				movzx	eax,ax
				mov		ecx,BN_CLICKED
				shl		ecx,16
				or		eax,ecx
				invoke SendMessage,[ebx].EDIT.hpar,WM_COMMAND,eax,[ebx].EDIT.hcol
				invoke SetFocus,[ebx].EDIT.focus
			.endif
		.else
			.if fControl
				invoke SendMessage,hWin,WM_VSCROLL,SB_PAGEUP,[esi].RAEDT.hvscroll
			.else
				.if !([ebx].EDIT.nMode&MODE_BLOCK)
					mov		eax,[ebx].EDIT.cpMin
					push	eax
					.if eax>[ebx].EDIT.cpMax && !fShift
						xchg	eax,[ebx].EDIT.cpMax
						mov		[ebx].EDIT.cpMin,eax
						invoke SetCaret,ebx,[esi].RAEDT.cpy
					.endif
					invoke GetCaretPos,addr pt
					mov		eax,[esi].RAEDT.rc.bottom
					mov		ecx,[ebx].EDIT.fntinfo.fntht
					xor		edx,edx
					div		ecx
					mul		ecx
					.if eax>[esi].RAEDT.cpy
						sub		eax,[esi].RAEDT.cpy
						sub		pt.y,eax
						mov		[esi].RAEDT.cpy,0
					.else
						sub		[esi].RAEDT.cpy,eax
					.endif
					mov		eax,[esi].RAEDT.cpxmax
					add		eax,[ebx].EDIT.selbarwt
					add		eax,[ebx].EDIT.linenrwt
					sub		eax,[ebx].EDIT.cpx
					invoke GetCharFromPos,ebx,[esi].RAEDT.cpy,eax,pt.y
					push	eax
					inc		eax
					invoke IsCharLeadByte,ebx,eax
					pop		edx
					add		edx,eax
					mov		eax,edx
					mov		[ebx].EDIT.cpMin,eax
					.if !fShift
						mov		[ebx].EDIT.cpMax,eax
					.endif
					invoke SetCaretVisible,hWin,[esi].RAEDT.cpy
					invoke SetCaret,ebx,[esi].RAEDT.cpy
					pop		eax
					.if eax!=[ebx].EDIT.cpMin
						invoke InvalidateEdit,ebx,[ebx].EDIT.edta.hwnd
						invoke InvalidateEdit,ebx,[ebx].EDIT.edtb.hwnd
						invoke SelChange,ebx,SEL_TEXT
						inc		nUndoid
					.endif
				.else
					invoke GetBlockRects,ebx,addr oldrects
					mov		eax,[esi].RAEDT.rc.bottom
					sub		eax,[esi].RAEDT.rc.top
					mov		ecx,[ebx].EDIT.fntinfo.fntht
					xor		edx,edx
					div		ecx
					mov		edx,[ebx].EDIT.blrg.lnMin
					.if edx>eax
						sub		edx,eax
					.else
						xor		edx,edx
					.endif
					mov		eax,[ebx].EDIT.blrg.clMin
					mov		[ebx].EDIT.blrg.lnMin,edx
					.if !fShift
						mov		[ebx].EDIT.blrg.clMax,eax
						mov		[ebx].EDIT.blrg.lnMax,edx
					.endif
					invoke GetBlockCp,ebx,edx,eax
					mov		[ebx].EDIT.cpMin,eax
					mov		[ebx].EDIT.cpMax,eax
					invoke GetCharPtr,ebx,eax
					invoke InvalidateBlock,ebx,addr oldrects
					invoke SetCaretVisible,hWin,[esi].RAEDT.cpy
					invoke SetCaret,ebx,[esi].RAEDT.cpy
					invoke SelChange,ebx,SEL_TEXT
					inc		nUndoid
				.endif
			.endif
		.endif
	.elseif eax==CMD_PAGE_DOWN
		.if fAlt
			.if fControl && !fShift
				;PgDn, expand
				invoke SendMessage,[ebx].EDIT.hpar,WM_COMMAND,-2,0
				mov		ax,-3
				movzx	eax,ax
				mov		ecx,BN_CLICKED
				shl		ecx,16
				or		eax,ecx
				invoke SendMessage,[ebx].EDIT.hpar,WM_COMMAND,eax,[ebx].EDIT.hexp
				invoke SetFocus,[ebx].EDIT.focus
			.endif
		.else
			.if fControl
				invoke SendMessage,hWin,WM_VSCROLL,SB_PAGEDOWN,[esi].RAEDT.hvscroll
			.else
				.if !([ebx].EDIT.nMode&MODE_BLOCK)
					mov		eax,[ebx].EDIT.cpMin
					push	eax
					.if eax<[ebx].EDIT.cpMax && !fShift
						xchg	eax,[ebx].EDIT.cpMax
						mov		[ebx].EDIT.cpMin,eax
						invoke SetCaret,ebx,[esi].RAEDT.cpy
					.endif
					invoke GetCaretPos,addr pt
					mov		eax,[esi].RAEDT.rc.bottom
					mov		ecx,[ebx].EDIT.fntinfo.fntht
					xor		edx,edx
					div		ecx
					mul		ecx
					push	eax
					mov		eax,[ebx].EDIT.rpLineFree
					shr		eax,2
					sub		eax,[ebx].EDIT.nHidden
					mov		ecx,[ebx].EDIT.fntinfo.fntht
					mul		ecx
					pop		ecx
					sub		eax,ecx
					add		ecx,[esi].RAEDT.cpy
					.if sdword ptr eax>=ecx
						mov		[esi].RAEDT.cpy,ecx
						mov		eax,[esi].RAEDT.cpxmax
						add		eax,[ebx].EDIT.selbarwt
						add		eax,[ebx].EDIT.linenrwt
						sub		eax,[ebx].EDIT.cpx
						invoke GetCharFromPos,ebx,[esi].RAEDT.cpy,eax,pt.y
						push	eax
						inc		eax
						invoke IsCharLeadByte,ebx,eax
						pop		edx
						add		edx,eax
						mov		eax,edx
						mov		[ebx].EDIT.cpMin,eax
						.if !fShift
							mov		[ebx].EDIT.cpMax,eax
						.endif
						invoke SetCaretVisible,hWin,[esi].RAEDT.cpy
						invoke SetCaret,ebx,[esi].RAEDT.cpy
					.else
						.if sdword ptr eax<0
							xor		eax,eax
						.endif
						mov		ecx,[esi].RAEDT.cpy
						mov		[esi].RAEDT.cpy,eax
						sub		eax,ecx
						sub		eax,[esi].RAEDT.rc.bottom
						neg		eax
						add		pt.y,eax
						mov		eax,[esi].RAEDT.cpxmax
						add		eax,[ebx].EDIT.selbarwt
						add		eax,[ebx].EDIT.linenrwt
						sub		eax,[ebx].EDIT.cpx
						invoke GetCharFromPos,ebx,[esi].RAEDT.cpy,eax,pt.y
						push	eax
						inc		eax
						invoke IsCharLeadByte,ebx,eax
						pop		edx
						add		edx,eax
						mov		eax,edx
						mov		[ebx].EDIT.cpMin,eax
						.if !fShift
							mov		[ebx].EDIT.cpMax,eax
						.endif
						invoke SetCaret,ebx,[esi].RAEDT.cpy
					.endif
					pop		eax
					.if eax!=[ebx].EDIT.cpMin
						invoke InvalidateEdit,ebx,[ebx].EDIT.edta.hwnd
						invoke InvalidateEdit,ebx,[ebx].EDIT.edtb.hwnd
						invoke SelChange,ebx,SEL_TEXT
						inc		nUndoid
					.endif
				.else
					invoke GetBlockRects,ebx,addr oldrects
					mov		eax,[esi].RAEDT.rc.bottom
					sub		eax,[esi].RAEDT.rc.top
					mov		ecx,[ebx].EDIT.fntinfo.fntht
					xor		edx,edx
					div		ecx
					mov		edx,[ebx].EDIT.blrg.lnMin
					add		edx,eax
					mov		eax,[ebx].EDIT.rpLineFree
					shr		eax,2
					.if edx>eax
						mov		edx,eax
					.endif
					mov		eax,[ebx].EDIT.blrg.clMin
					mov		[ebx].EDIT.blrg.lnMin,edx
					.if !fShift
						mov		[ebx].EDIT.blrg.clMax,eax
						mov		[ebx].EDIT.blrg.lnMax,edx
					.endif
					invoke GetBlockCp,ebx,edx,eax
					mov		[ebx].EDIT.cpMin,eax
					mov		[ebx].EDIT.cpMax,eax
					invoke GetCharPtr,ebx,eax
					invoke InvalidateBlock,ebx,addr oldrects
					invoke SetCaretVisible,hWin,[esi].RAEDT.cpy
					invoke SetCaret,ebx,[esi].RAEDT.cpy
					invoke SelChange,ebx,SEL_TEXT
					inc		nUndoid
				.endif
			.endif
		.endif
	.elseif eax==CMD_HOME
		.if fAlt
			.if fControl && !fShift
				;Home, jump to split
				.if [ebx].EDIT.nsplitt
					mov		eax,[ebx].EDIT.cpMin
					mov		[esi].RAEDT.cp,eax
					mov		eax,hWin
					.if eax==[ebx].EDIT.edtb.hwnd
						mov		eax,[ebx].EDIT.edta.cp
						mov		[ebx].EDIT.cpMin,eax
						mov		[ebx].EDIT.cpMax,eax
						invoke SetFocus,[ebx].EDIT.edta.hwnd
					.else
						mov		eax,[ebx].EDIT.edtb.cp
						mov		[ebx].EDIT.cpMin,eax
						mov		[ebx].EDIT.cpMax,eax
						invoke SetFocus,[ebx].EDIT.edtb.hwnd
					.endif
					invoke SelChange,ebx,SEL_TEXT
					inc		nUndoid
				.endif
			.endif
		.else
			.if !([ebx].EDIT.nMode&MODE_BLOCK)
				mov		[esi].RAEDT.cpxmax,0
				mov		[ebx].EDIT.cpx,0
				.if fControl
					xor		eax,eax
					mov		[esi].RAEDT.cpy,eax
				.else
					mov		eax,[ebx].EDIT.cpMin
					.if eax>[ebx].EDIT.cpMax && !fShift
						xchg	eax,[ebx].EDIT.cpMax
						mov		[ebx].EDIT.cpMin,eax
						invoke SetCaret,ebx,[esi].RAEDT.cpy
						invoke SetCaretVisible,hWin,[esi].RAEDT.cpy
					.endif
					invoke GetCaretPos,addr pt
					invoke GetCharFromPos,ebx,[esi].RAEDT.cpy,0,pt.y
					push	eax
					invoke SkipSpace,ebx,eax,FALSE
					pop		edx
					.if eax==[ebx].EDIT.cpMin
						mov		eax,edx
					.endif
				.endif
				mov		[ebx].EDIT.cpMin,eax
				.if !fShift
					mov		[ebx].EDIT.cpMax,eax
				.endif
				invoke SetCaret,ebx,[esi].RAEDT.cpy
				invoke InvalidateEdit,ebx,[ebx].EDIT.edta.hwnd
				invoke InvalidateEdit,ebx,[ebx].EDIT.edtb.hwnd
			.else
				invoke GetBlockRects,ebx,addr oldrects
				.if fControl
					invoke GetCharFromPos,ebx,0,[ebx].EDIT.cpx,0
				.else
					invoke GetCaretPos,addr pt
					invoke GetCharFromPos,ebx,[esi].RAEDT.cpy,[ebx].EDIT.cpx,pt.y
				.endif
				invoke SetBlockFromCp,ebx,eax,fShift
				invoke InvalidateBlock,ebx,addr oldrects
				invoke SetCaretVisible,hWin,[esi].RAEDT.cpy
				invoke SetCaret,ebx,[esi].RAEDT.cpy
			.endif
			invoke SelChange,ebx,SEL_TEXT
			inc		nUndoid
		.endif
	.elseif eax==CMD_END
		.if fAlt
			.if fControl && !fShift
				;End, split
				mov		eax,1ffH
				.if [ebx].EDIT.fsplitt
					xor		eax,eax
				.endif
				invoke SendMessage,[ebx].EDIT.hwnd,REM_SETSPLIT,eax,0
			.endif
		.else
			.if !([ebx].EDIT.nMode&MODE_BLOCK)
				mov		eax,[ebx].EDIT.cpMin
				.if eax<[ebx].EDIT.cpMax && !fShift
					xchg	eax,[ebx].EDIT.cpMax
					dec		eax
					mov		[ebx].EDIT.cpMin,eax
					invoke SetCaret,ebx,[esi].RAEDT.cpy
				.elseif eax>[ebx].EDIT.cpMax && !fShift
					dec		[ebx].EDIT.cpMin
					invoke SetCaret,ebx,[esi].RAEDT.cpy
				.endif
				mov		[esi].RAEDT.cpxmax,999999999
				.if fControl
					invoke GetCharFromPos,ebx,[esi].RAEDT.cpy,999999999,999999999
				.else
					invoke GetCaretPos,addr pt
					invoke GetCharFromPos,ebx,[esi].RAEDT.cpy,999999999,pt.y
					push	eax
					invoke SkipSpace,ebx,eax,TRUE
					pop		edx
					.if eax==[ebx].EDIT.cpMin
						mov		eax,edx
					.endif
				.endif
				mov		[ebx].EDIT.cpMin,eax
				.if !fShift
					mov		[ebx].EDIT.cpMax,eax
				.endif
				invoke SetCaretVisible,hWin,[esi].RAEDT.cpy
				invoke SetCaret,ebx,[esi].RAEDT.cpy
				invoke InvalidateEdit,ebx,[ebx].EDIT.edta.hwnd
				invoke InvalidateEdit,ebx,[ebx].EDIT.edtb.hwnd
				invoke SetCpxMax,ebx,hWin
			.else
				invoke GetBlockRects,ebx,addr oldrects
				.if fControl
					invoke GetCharFromPos,ebx,[esi].RAEDT.cpy,999999999,999999999
				.else
					invoke GetCaretPos,addr pt
					invoke GetCharFromPos,ebx,[esi].RAEDT.cpy,999999999,pt.y
				.endif
				invoke SetBlockFromCp,ebx,eax,fShift
				invoke InvalidateBlock,ebx,addr oldrects
				invoke SetCaretVisible,hWin,[esi].RAEDT.cpy
				invoke SetCaret,ebx,[esi].RAEDT.cpy
			.endif
			invoke SelChange,ebx,SEL_TEXT
			inc		nUndoid
		.endif
	.elseif eax==CMD_INSERT
		.if fAlt
			.if fControl && !fShift
				;Insert, show/hide linenumbers
				invoke IsDlgButtonChecked,[ebx].EDIT.hwnd,-2
				.if eax
					mov		eax,BST_UNCHECKED
				.else
					mov		eax,BST_CHECKED
				.endif
				invoke CheckDlgButton,[ebx].EDIT.hwnd,-2,eax
				mov		ax,-2
				movzx	eax,ax
				mov		ecx,BN_CLICKED
				shl		ecx,16
				or		eax,ecx
				invoke SendMessage,[ebx].EDIT.hwnd,WM_COMMAND,eax,[ebx].EDIT.hlin
				invoke SetCaret,ebx,[esi].RAEDT.cpy
				invoke SetCaretVisible,hWin,[esi].RAEDT.cpy
			.endif
		.else
			.if !fShift && !fControl
				;Insert
				xor		[ebx].EDIT.fOvr,1
				.if [ebx].EDIT.fOvr
					or		[ebx].EDIT.nMode,MODE_OVERWRITE
				.else
					and		[ebx].EDIT.nMode,-1 xor MODE_OVERWRITE
				.endif
				invoke SelChange,ebx,SEL_TEXT
			.elseif fShift && !fControl
				;Shift+Insert, Paste
				inc		nUndoid
				invoke IsSelectionLocked,ebx,[ebx].EDIT.cpMin,[ebx].EDIT.cpMax
				.if eax!=0
					jmp		ErrBeep
				.endif
				invoke Paste,ebx,hWin,NULL
				inc		nUndoid
			.elseif !fShift && fControl
				;Ctrl+Insert, Copy
				invoke Copy,ebx
			.endif
		.endif
	.elseif eax==CMD_DELETE
		.if fAlt
			.if fControl && !fShift
			.endif
		.else
			.if ((!fShift && !fControl) || (!fShift && fControl) || (fShift && fControl))
				;Delete. Ctrl+Delete, delete to end of word. Ctrl+Shift+Delete, delete to end of line.
				.if !([ebx].EDIT.nMode&MODE_BLOCK)
					mov		eax,[ebx].EDIT.cpMin
					.if fControl
						.if eax>[ebx].EDIT.cpMax
							xchg	[ebx].EDIT.cpMax,eax
							mov		[ebx].EDIT.cpMin,eax
						.endif
						.if fShift
							invoke GetLineEnd,ebx,[ebx].EDIT.cpMax
						.else
							invoke GetWordEnd,ebx,[ebx].EDIT.cpMax,0
						.endif
						mov		[ebx].EDIT.cpMax,eax
					.endif
					mov		eax,[ebx].EDIT.cpMin
					.if eax!=[ebx].EDIT.cpMax
						;Selection
						invoke IsSelectionLocked,ebx,[ebx].EDIT.cpMin,[ebx].EDIT.cpMax
						.if eax!=0
							jmp		ErrBeep
						.endif
						inc		nUndoid
						invoke DeleteSelection,ebx,[ebx].EDIT.cpMin,[ebx].EDIT.cpMax
						mov		[ebx].EDIT.cpMin,eax
						mov		[ebx].EDIT.cpMax,eax
						.if eax<[ebx].EDIT.edta.cp
							mov		[ebx].EDIT.edta.cp,eax
						.endif
						.if eax<[ebx].EDIT.edtb.cp
							mov		[ebx].EDIT.edtb.cp,eax
						.endif
						invoke GetCharPtr,ebx,[ebx].EDIT.cpMin
						invoke GetYpFromLine,ebx,edx
						.if eax<[ebx].EDIT.edta.cpy
							mov		[ebx].EDIT.edta.cpy,eax
						.endif
						.if eax<[ebx].EDIT.edtb.cpy
							mov		[ebx].EDIT.edtb.cpy,eax
						.endif
						invoke SetCaretVisible,hWin,[esi].RAEDT.cpy
						invoke SetCaret,ebx,[esi].RAEDT.cpy
						invoke InvalidateEdit,ebx,[ebx].EDIT.edta.hwnd
						invoke InvalidateEdit,ebx,[ebx].EDIT.edtb.hwnd
						inc		nUndoid
					.else
						;Single char
						inc		eax
						invoke IsSelectionLocked,ebx,[ebx].EDIT.cpMin,eax
						.if eax!=0
							jmp		ErrBeep
						.endif
						invoke GetChar,ebx,[ebx].EDIT.cpMin
						.if al==VK_RETURN
							invoke GetBookMark,ebx,[ebx].EDIT.line
							.if eax==2 || eax==8
								invoke Expand,ebx,[ebx].EDIT.line
							.endif
						.else
							invoke IsCharLeadByte,ebx,[ebx].EDIT.cpMin
							.if eax
								invoke DeleteChar,ebx,[ebx].EDIT.cpMin
								invoke SaveUndo,ebx,UNDO_DELETE,[ebx].EDIT.cpMin,eax,1
							.endif
						.endif
						invoke DeleteChar,ebx,[ebx].EDIT.cpMin
						push	eax
						invoke SaveUndo,ebx,UNDO_DELETE,[ebx].EDIT.cpMin,eax,1
						pop		eax
						.if eax==VK_RETURN
							invoke InvalidateEdit,ebx,[ebx].EDIT.edta.hwnd
							invoke InvalidateEdit,ebx,[ebx].EDIT.edtb.hwnd
						.else
							invoke InvalidateLine,ebx,hWin,[ebx].EDIT.line
						.endif
					.endif
				.else
					;Block
					invoke IsSelectionLocked,ebx,[ebx].EDIT.cpMin,[ebx].EDIT.cpMax
					.if eax!=0
						jmp		ErrBeep
					.endif
					inc		nUndoid
					mov		eax,[ebx].EDIT.blrg.clMin
					.if eax==[ebx].EDIT.blrg.clMax
						inc		[ebx].EDIT.blrg.clMax
					.endif
					invoke DeleteSelectionBlock,ebx,[ebx].EDIT.blrg.lnMin,[ebx].EDIT.blrg.clMin,[ebx].EDIT.blrg.lnMax,[ebx].EDIT.blrg.clMax
					mov		eax,[ebx].EDIT.blrg.clMin
					.if eax>[ebx].EDIT.blrg.clMax
						mov		eax,[ebx].EDIT.blrg.clMax
					.endif
					mov		edx,[ebx].EDIT.blrg.lnMin
					.if edx>[ebx].EDIT.blrg.lnMax
						mov		edx,[ebx].EDIT.blrg.lnMax
					.endif
					mov		[ebx].EDIT.blrg.clMin,eax
					mov		[ebx].EDIT.blrg.lnMin,edx
					mov		[ebx].EDIT.blrg.clMax,eax
					mov		[ebx].EDIT.blrg.lnMax,edx
					invoke GetBlockCp,ebx,edx,eax
					mov		[ebx].EDIT.cpMin,eax
					mov		[ebx].EDIT.cpMax,eax
					invoke GetCharPtr,ebx,[ebx].EDIT.cpMin
					invoke SetCaretVisible,hWin,[esi].RAEDT.cpy
					invoke SetCaret,ebx,[esi].RAEDT.cpy
					invoke InvalidateEdit,ebx,[ebx].EDIT.edta.hwnd
					invoke InvalidateEdit,ebx,[ebx].EDIT.edtb.hwnd
					inc		nUndoid
				.endif
				invoke SetCpxMax,ebx,hWin
				invoke SelChange,ebx,SEL_TEXT
			.elseif fShift && !fControl
				;Shift+Delete, Cut
				invoke IsSelectionLocked,ebx,[ebx].EDIT.cpMin,[ebx].EDIT.cpMax
				.if eax!=0
					jmp		ErrBeep
				.endif
				inc		nUndoid
				invoke Cut,ebx,hWin
				inc		nUndoid
			.endif
		.endif
	.elseif eax==CMD_BACKSPACE
		.if fAlt
			.if fControl && !fShift
			.endif
		.elseif fControl
			;Ctrl+Backspace, Delete to start of word.
			;Ctrl+Shift+Backspace, Delete to start of line.
			.if !([ebx].EDIT.nMode&MODE_BLOCK)
				mov		eax,[ebx].EDIT.cpMin
				.if eax>[ebx].EDIT.cpMax
					xchg	[ebx].EDIT.cpMax,eax
					mov		[ebx].EDIT.cpMin,eax
				.endif
				.if fShift
					invoke GetLineStart,ebx,[ebx].EDIT.cpMin
				.else
					invoke GetWordStart,ebx,[ebx].EDIT.cpMin,0
				.endif
				.if eax && eax==[ebx].EDIT.cpMin
					dec		eax
				.endif
				mov		[ebx].EDIT.cpMin,eax
				.if eax!=[ebx].EDIT.cpMax
					invoke IsSelectionLocked,ebx,[ebx].EDIT.cpMin,[ebx].EDIT.cpMax
					.if eax!=0
						jmp		ErrBeep
					.endif
					inc		nUndoid
					invoke DeleteSelection,ebx,[ebx].EDIT.cpMin,[ebx].EDIT.cpMax
					mov		[ebx].EDIT.cpMin,eax
					mov		[ebx].EDIT.cpMax,eax
					invoke GetCharPtr,ebx,[ebx].EDIT.cpMin
					invoke SetCaretVisible,hWin,[esi].RAEDT.cpy
					invoke SetCaret,ebx,[esi].RAEDT.cpy
					invoke InvalidateEdit,ebx,[ebx].EDIT.edta.hwnd
					invoke InvalidateEdit,ebx,[ebx].EDIT.edtb.hwnd
					invoke SetCpxMax,ebx,hWin
					invoke SelChange,ebx,SEL_TEXT
					inc		nUndoid
				.endif
			.endif
		.endif
	.endif
  Ex:
	ret

ErrBeep:
	invoke MessageBeep,MB_ICONHAND
	xor		eax,eax
	ret

EditFunc endp

RAEditProc proc uses ebx esi edi,hWin:HWND,uMsg:UINT,wParam:WPARAM,lParam:LPARAM
	LOCAL	sinf:SCROLLINFO
	LOCAL	pt:POINT
	LOCAL	fAlt:DWORD
	LOCAL	fShift:DWORD
	LOCAL	fControl:DWORD
	LOCAL	fSel:DWORD
	LOCAL	cp:DWORD
	LOCAL	cpOldMin:DWORD
	LOCAL	cpOldMax:DWORD
	LOCAL	nOldLine:DWORD
	LOCAL	hCur:DWORD
	LOCAL	rect:RECT
	LOCAL	oldrects[2]:RECT

	;Get memory pointers
	invoke GetWindowLong,hWin,0
	mov		ebx,eax
	.if eax
		mov		eax,hWin
		.if eax==[ebx].EDIT.edta.hwnd
			lea		esi,[ebx].EDIT.edta
		.else
			lea		esi,[ebx].EDIT.edtb
		.endif
	.else
		.if uMsg!=WM_CREATE
			jmp		ExDef
		.endif
	.endif
	mov		eax,uMsg
	.if eax==WM_PAINT
		.if [esi].RAEDT.rc.bottom
			.if fSize
				mov		fSize,FALSE
				invoke RAEditPaint,hWin
			.else
				.if !([ebx].EDIT.fstyle&STYLE_NOBACKBUFFER)
					invoke RAEditPaint,hWin
				.else
					invoke GetUpdateRect,hWin,addr rect,FALSE
					mov		eax,rect.bottom
					sub		eax,rect.top
					mov		edx,[ebx].EDIT.fntinfo.fntht
					shl		edx,2
					.if eax<=edx
						invoke RAEditPaint,hWin
					.else
						invoke RAEditPaintNoBuff,hWin
					.endif
				.endif
			.endif
			call	NestedProc_SetScroll
		.endif
		xor		eax,eax
		jmp		Ex
	.elseif eax==WM_KEYDOWN
		invoke GetKeyState,VK_MENU
		and		eax,80h
		mov		fAlt,eax
		invoke GetKeyState,VK_CONTROL
		and		eax,80h
		mov		fControl,eax
		invoke GetKeyState,VK_SHIFT
		and		eax,80h
		mov		fShift,eax
		mov		eax,[ebx].EDIT.cpMin
		mov		cpOldMin,eax
		mov		edx,[ebx].EDIT.cpMax
		mov		cpOldMax,edx
		sub		edx,eax
		mov		fSel,edx
		mov		edx,wParam
		mov		eax,lParam
		shr		eax,16
		and		eax,3FFh
		.if edx==26h && (eax==148h || eax==48h)
			;Up
			invoke EditFunc,hWin,CMD_LINE_UP,fAlt,fShift,fControl
		.elseif edx==28h && (eax==150h || eax==50h)
			;Down
			invoke EditFunc,hWin,CMD_LINE_DOWN,fAlt,fShift,fControl
		.elseif edx==25h && (eax==14Bh || eax==4Bh)
			;Left
			invoke EditFunc,hWin,CMD_LEFT,fAlt,fShift,fControl
		.elseif edx==27h && (eax==14Dh || eax==4Dh)
			;Right
			invoke EditFunc,hWin,CMD_RIGHT,fAlt,fShift,fControl
		.elseif edx==21h && (eax==149h || eax==49h)
			;PgUp
			invoke EditFunc,hWin,CMD_PAGE_UP,fAlt,fShift,fControl
		.elseif edx==22h && (eax==151h || eax==51h)
			;PgDn
			invoke EditFunc,hWin,CMD_PAGE_DOWN,fAlt,fShift,fControl
		.elseif edx==24h && (eax==147h || eax==47h)
			;Home
			invoke EditFunc,hWin,CMD_HOME,fAlt,fShift,fControl
		.elseif edx==23h && (eax==14Fh || eax==4Fh)
			;End
			invoke EditFunc,hWin,CMD_END,fAlt,fShift,fControl
		.elseif edx==2Dh && (eax==152h || eax==52h)
			;Insert
			invoke EditFunc,hWin,CMD_INSERT,fAlt,fShift,fControl
		.elseif edx==2Eh && (eax==153h || eax==53h)
			;Delete
			invoke EditFunc,hWin,CMD_DELETE,fAlt,fShift,fControl
		.elseif edx==43h && fControl && !fShift && !fAlt
			;Ctrl+C, Copy
			invoke Copy,ebx
		.elseif edx==58h && fControl && !fShift && !fAlt
			;Ctrl+X, Cut
			invoke IsSelectionLocked,ebx,[ebx].EDIT.cpMin,[ebx].EDIT.cpMax
			.if eax!=0
				jmp		ErrBeep
			.endif
			inc		nUndoid
			invoke Cut,ebx,hWin
			inc		nUndoid
		.elseif edx==56h && fControl && !fShift && !fAlt
			;Ctrl+V, Paste
			invoke IsSelectionLocked,ebx,[ebx].EDIT.cpMin,[ebx].EDIT.cpMax
			.if eax!=0
				jmp		ErrBeep
			.endif
			inc		nUndoid
			invoke Paste,ebx,hWin,NULL
			inc		nUndoid
		.elseif edx==41h && fControl && !fShift && !fAlt
			;Ctrl+A, Select all
			.if !([ebx].EDIT.nMode&MODE_BLOCK)
				invoke GetCharPtr,ebx,-1
				mov		[ebx].EDIT.cpMax,ecx
				invoke GetCharPtr,ebx,0
				mov		[ebx].EDIT.cpMin,ecx
				invoke SetCaret,ebx,[esi].RAEDT.cpy
				invoke InvalidateEdit,ebx,[ebx].EDIT.edta.hwnd
				invoke InvalidateEdit,ebx,[ebx].EDIT.edtb.hwnd
				invoke SelChange,ebx,SEL_TEXT
				inc		nUndoid
			.endif
		.elseif edx==5Ah && fControl && !fShift && !fAlt
			;Ctrl+Z, Undo
			inc		nUndoid
			invoke Undo,ebx,hWin
			inc		nUndoid
		.elseif edx==59h && fControl && !fShift && !fAlt
			;Ctrl+Y, Redo
			inc		nUndoid
			invoke Redo,ebx,hWin
			inc		nUndoid
		.elseif edx==08h && eax==0Eh
			;Backspace
			invoke EditFunc,hWin,CMD_BACKSPACE,fAlt,fShift,fControl
		.else
			jmp		ExDef
		.endif
		xor		eax,eax
		jmp		Ex
	.elseif eax==WM_CHAR
		mov		[ebx].EDIT.cpselbar,-1
		.if [ebx].EDIT.cpbrst!=-1 || [ebx].EDIT.cpbren!=-1
			mov		[ebx].EDIT.cpbrst,-1
			mov		[ebx].EDIT.cpbren,-1
			invoke InvalidateEdit,ebx,[ebx].EDIT.edta.hwnd
			invoke InvalidateEdit,ebx,[ebx].EDIT.edtb.hwnd
		.endif
		.if !([ebx].EDIT.nMode&MODE_BLOCK)
			mov		eax,wParam
			.if (eax>=VK_SPACE || eax==VK_RETURN || eax==VK_TAB) && eax!=7Fh
				invoke IsSelectionLocked,ebx,[ebx].EDIT.cpMin,[ebx].EDIT.cpMax
				.if eax!=0
					jmp		ErrBeep
				.endif
				mov		eax,[ebx].EDIT.cpMin
				sub		eax,[ebx].EDIT.cpMax
				push	eax
				invoke DeleteSelection,ebx,[ebx].EDIT.cpMin,[ebx].EDIT.cpMax
				mov		[ebx].EDIT.cpMin,eax
				mov		[ebx].EDIT.cpMax,eax
				mov		ecx,1
				.if wParam==VK_TAB && [ebx].EDIT.fExpandTab
					mov		wParam,VK_SPACE
					invoke GetTabPos,ebx,[ebx].EDIT.cpMin
					mov		ecx,[ebx].EDIT.nTab
					sub		ecx,eax
				.endif
			  @@:
				push	ecx
				push	[ebx].EDIT.cpMin
				invoke GetCharPtr,ebx,[ebx].EDIT.cpMin
				invoke InsertChar,ebx,[ebx].EDIT.cpMin,wParam
				pop		ecx
				.if !eax
					invoke SaveUndo,ebx,UNDO_INSERT,ecx,wParam,1
				.else
					invoke SaveUndo,ebx,UNDO_OVERWRITE,ecx,eax,1
				.endif
				mov		eax,[ebx].EDIT.cpMin
				inc		eax
				mov		[ebx].EDIT.cpMin,eax
				mov		[ebx].EDIT.cpMax,eax
				pop		ecx
				dec		ecx
				.if ecx!=0
					jmp @b
				.endif
				.if wParam==VK_RETURN && [ebx].EDIT.fIndent
					invoke AutoIndent,ebx
				.endif
				invoke GetCharPtr,ebx,[ebx].EDIT.cpMin
				invoke SetCaretVisible,hWin,[esi].RAEDT.cpy
				push	eax
				.if !eax
					invoke InvalidateLine,ebx,[ebx].EDIT.edta.hwnd,[ebx].EDIT.line
					invoke InvalidateLine,ebx,[ebx].EDIT.edtb.hwnd,[ebx].EDIT.line
				.endif
				invoke SetCaret,ebx,[esi].RAEDT.cpy
				pop		eax
				pop		edx
				.if eax && !edx
					.if wParam==VK_RETURN
						invoke InvalidateEdit,ebx,[ebx].EDIT.edta.hwnd
						invoke InvalidateEdit,ebx,[ebx].EDIT.edtb.hwnd
					.else
						invoke InvalidateLine,ebx,[ebx].EDIT.edta.hwnd,[ebx].EDIT.line
						invoke InvalidateLine,ebx,[ebx].EDIT.edtb.hwnd,[ebx].EDIT.line
					.endif
				.elseif (eax && edx) || wParam==VK_RETURN
					invoke InvalidateEdit,ebx,[ebx].EDIT.edta.hwnd
					invoke InvalidateEdit,ebx,[ebx].EDIT.edtb.hwnd
				.endif
				invoke SetCpxMax,ebx,hWin
				invoke SelChange,ebx,SEL_TEXT
				mov		eax,[ebx].EDIT.cpMin
				dec		eax
				invoke BracketMatch,ebx,wParam,eax
			.elseif eax==08h
				mov		eax,[ebx].EDIT.cpMin
				.if eax!=[ebx].EDIT.cpMax || eax
					invoke IsSelectionLocked,ebx,[ebx].EDIT.cpMin,[ebx].EDIT.cpMax
					.if eax!=0
						jmp		ErrBeep
					.endif
					mov		eax,[ebx].EDIT.cpMin
					.if eax!=[ebx].EDIT.cpMax
						invoke DeleteSelection,ebx,[ebx].EDIT.cpMin,[ebx].EDIT.cpMax
						mov		[ebx].EDIT.cpMin,eax
						mov		[ebx].EDIT.cpMax,eax
						invoke GetCharPtr,ebx,[ebx].EDIT.cpMin
						invoke SetCaretVisible,hWin,[esi].RAEDT.cpy
						invoke SetCaret,ebx,[esi].RAEDT.cpy
						invoke InvalidateEdit,ebx,[ebx].EDIT.edta.hwnd
						invoke InvalidateEdit,ebx,[ebx].EDIT.edtb.hwnd
					.elseif eax
						dec		eax
						invoke IsSelectionLocked,ebx,eax,eax
						.if eax!=0
							jmp		ErrBeep
						.endif
						dec		[ebx].EDIT.cpMin
						dec		[ebx].EDIT.cpMax
						invoke GetChar,ebx,[ebx].EDIT.cpMin
						.if al==VK_RETURN
							invoke IsLineHidden,ebx,[ebx].EDIT.line
							.if eax
								invoke PreviousBookMark,ebx,[ebx].EDIT.line,2
								.if eax!=-1
									invoke Expand,ebx,eax
								.endif
							.endif
							invoke DeleteChar,ebx,[ebx].EDIT.cpMin
							mov		wParam,eax
							invoke SaveUndo,ebx,UNDO_BACKDELETE,[ebx].EDIT.cpMin,eax,1
						.else
							mov		eax,[ebx].EDIT.cpMin
							.if eax
								dec		eax
								invoke IsCharLeadByte,ebx,eax
								.if eax
									invoke DeleteChar,ebx,[ebx].EDIT.cpMin
									mov		wParam,eax
									invoke SaveUndo,ebx,UNDO_BACKDELETE,[ebx].EDIT.cpMin,eax,1
									dec		[ebx].EDIT.cpMin
									dec		[ebx].EDIT.cpMax
								.endif
							.endif
							invoke DeleteChar,ebx,[ebx].EDIT.cpMin
							mov		wParam,eax
							invoke SaveUndo,ebx,UNDO_BACKDELETE,[ebx].EDIT.cpMin,eax,1
						.endif
						invoke GetCharPtr,ebx,[ebx].EDIT.cpMin
						invoke SetCaret,ebx,[esi].RAEDT.cpy
						.if wParam==VK_RETURN
							.if sdword ptr eax<0
								add		[esi].RAEDT.cpy,eax
								invoke SetCaret,ebx,[esi].RAEDT.cpy
							.endif
							invoke SetCaretVisible,hWin,[esi].RAEDT.cpy
							invoke InvalidateEdit,ebx,[ebx].EDIT.edta.hwnd
							invoke InvalidateEdit,ebx,[ebx].EDIT.edtb.hwnd
						.else
							invoke SetCaretVisible,hWin,[esi].RAEDT.cpy
							invoke InvalidateLine,ebx,[ebx].EDIT.edta.hwnd,[ebx].EDIT.line
							invoke InvalidateLine,ebx,[ebx].EDIT.edtb.hwnd,[ebx].EDIT.line
						.endif
					.endif
					invoke SetCpxMax,ebx,hWin
					invoke SelChange,ebx,SEL_TEXT
				.endif
			.endif
		.else
			mov		eax,wParam
			.if (eax>=VK_SPACE || eax==VK_TAB) && eax!=7Fh
				invoke IsSelectionLocked,ebx,[ebx].EDIT.cpMin,[ebx].EDIT.cpMax
				.if eax!=0
					jmp		ErrBeep
				.endif
				push	esi
				inc		nUndoid
				mov		eax,[ebx].EDIT.blrg.lnMin
				mov		edx,[ebx].EDIT.blrg.lnMax
				.if eax<edx
					xchg	eax,edx
				.endif
				sub		eax,edx
				inc		eax
				mov		edi,eax
				mov		eax,[ebx].EDIT.blrg.clMin
				mov		edx,[ebx].EDIT.blrg.clMax
				.if eax<edx
					xchg	eax,edx
				.endif
				sub		eax,edx
				.if !eax
					.if wParam==VK_TAB
						mov		eax,[ebx].EDIT.blrg.clMin
						mov		ecx,[ebx].EDIT.nTab
						xor		edx,edx
						div		ecx
						inc		eax
						mul		ecx
						sub		eax,[ebx].EDIT.blrg.clMin
						mov		cp,eax
						.if [ebx].EDIT.fExpandTab
							mov		wParam,VK_SPACE
						.else
							mov		eax,1
						.endif
					.else
						inc		eax
						mov		cp,eax
					.endif
				.else
					mov		cp,eax
				.endif
				mov		esi,eax
				add		eax,2
				mul		edi
				inc		eax
				invoke xGlobalAlloc,GMEM_FIXED or GMEM_ZEROINIT,eax
				push	eax
				mov		edx,eax
				mov		eax,wParam
				.while edi
					push	esi
					.while esi
						mov		[edx],al
						inc		edx
						dec		esi
					.endw
					mov		byte ptr [edx],0Dh
					inc		edx
					mov		byte ptr [edx],0Ah
					inc		edx
					pop		esi
					dec		edi
				.endw
				pop		eax
				push	eax
				invoke Paste,ebx,hWin,eax
				mov		eax,[ebx].EDIT.blrg.clMin
				.if eax==[ebx].EDIT.blrg.clMax
					add		eax,cp
					mov		[ebx].EDIT.blrg.clMin,eax
					mov		[ebx].EDIT.blrg.clMax,eax
					invoke GetBlockCp,ebx,[ebx].EDIT.blrg.lnMin,eax
					mov		[ebx].EDIT.cpMin,eax
					mov		[ebx].EDIT.cpMax,eax
				.else
					inc		nUndoid
				.endif
				pop		eax
				invoke GlobalFree,eax
				pop		esi
				invoke GetCharPtr,ebx,[ebx].EDIT.cpMin
				invoke SetCaretVisible,hWin,[esi].RAEDT.cpy
				invoke SetCaret,ebx,[esi].RAEDT.cpy
				invoke SelChange,ebx,SEL_TEXT
			.elseif eax==08h
				invoke IsSelectionLocked,ebx,[ebx].EDIT.cpMin,[ebx].EDIT.cpMax
				.if eax!=0
					jmp		ErrBeep
				.endif
				mov		eax,[ebx].EDIT.blrg.clMin
				.if eax==[ebx].EDIT.blrg.clMax && eax
					dec		[ebx].EDIT.blrg.clMin
				.endif
				invoke DeleteSelectionBlock,ebx,[ebx].EDIT.blrg.lnMin,[ebx].EDIT.blrg.clMin,[ebx].EDIT.blrg.lnMax,[ebx].EDIT.blrg.clMax
				mov		eax,[ebx].EDIT.blrg.clMin
				.if eax>[ebx].EDIT.blrg.clMax
					mov		eax,[ebx].EDIT.blrg.clMax
				.endif
				mov		[ebx].EDIT.blrg.clMin,eax
				mov		[ebx].EDIT.blrg.clMax,eax
				invoke GetBlockCp,ebx,[ebx].EDIT.blrg.lnMin,eax
				mov		[ebx].EDIT.cpMin,eax
				mov		[ebx].EDIT.cpMax,eax
				invoke GetCharPtr,ebx,[ebx].EDIT.cpMin
				invoke SetCaretVisible,hWin,[esi].RAEDT.cpy
				invoke SetCaret,ebx,[esi].RAEDT.cpy
				invoke InvalidateEdit,ebx,[ebx].EDIT.edta.hwnd
				invoke InvalidateEdit,ebx,[ebx].EDIT.edtb.hwnd
				invoke SelChange,ebx,SEL_TEXT
			.endif
		.endif
		xor		eax,eax
		jmp		Ex
	.elseif eax==WM_MOUSEMOVE
		mov		eax,wParam
		and		eax,MK_SHIFT
		mov		fShift,eax
		.if fOnSel
			invoke LoadCursor,0,IDC_ARROW
			invoke SetCursor,eax
		.endif
		invoke SendMessage,[ebx].EDIT.htt,TTM_ACTIVATE,FALSE,0
		invoke SendMessage,[ebx].EDIT.htt,TTM_ACTIVATE,TRUE,0
		invoke GetCursorPos,addr pt
		invoke ScreenToClient,hWin,addr pt
		.if fSelState==1 || fSelState==2 || fSelState==10
			;Selection, not on selbar
			.if fSelState==1
				mov		fSelState,2
			.endif
			.if wParam&MK_LBUTTON
				.if !tmr1.hwnd
					mov		eax,pt.x
					mov		edx,pt.y
					mov		ecx,[ebx].EDIT.selbarwt
					add		ecx,[ebx].EDIT.linenrwt
					.if eax>[esi].RAEDT.rc.right || sdword ptr eax<ecx || edx>[esi].RAEDT.rc.bottom
						.if sdword ptr edx>[esi].RAEDT.rc.bottom
							sub		edx,[esi].RAEDT.rc.bottom
							mov		eax,hWin
							mov		tmr1.hwnd,eax
							mov		tmr1.umsg,WM_VSCROLL
							mov		tmr1.wparam,SB_LINEDOWN
							mov		eax,[esi].RAEDT.hvscroll
							mov		tmr1.lparam,eax
						.elseif sdword ptr edx<0
							neg		edx
							mov		eax,hWin
							mov		tmr1.hwnd,eax
							mov		tmr1.umsg,WM_VSCROLL
							mov		tmr1.wparam,SB_LINEUP
							mov		eax,[esi].RAEDT.hvscroll
							mov		tmr1.lparam,eax
						.elseif sdword ptr eax>[esi].RAEDT.rc.right
							mov		edx,eax
							sub		edx,[esi].RAEDT.rc.right
							mov		eax,[ebx].EDIT.hwnd
							mov		tmr1.hwnd,eax
							mov		tmr1.umsg,WM_HSCROLL
							mov		tmr1.wparam,SB_LINEDOWN
							mov		eax,[ebx].EDIT.hhscroll
							mov		tmr1.lparam,eax
						.elseif sdword ptr eax<ecx
							mov		edx,ecx
							sub		edx,eax
							mov		eax,[ebx].EDIT.hwnd
							mov		tmr1.hwnd,eax
							mov		tmr1.umsg,WM_HSCROLL
							mov		tmr1.wparam,SB_LINEUP
							mov		eax,[ebx].EDIT.hhscroll
							mov		tmr1.lparam,eax
						.endif
						mov		eax,hWin
						mov		tmr2.hwnd,eax
						mov		eax,uMsg
						mov		tmr2.umsg,eax
						mov		eax,wParam
						mov		tmr2.wparam,eax
						mov		eax,lParam
						mov		tmr2.lparam,eax
						shl		edx,2
						mov		eax,100
						sub		eax,edx
						.if sdword ptr eax<10
							mov		eax,10
						.endif
						invoke SetTimer,NULL,0,eax,offset TimerProc
						mov		TimerID,eax
					.endif
				.endif
			.else
				xor		eax,eax
				mov		tmr1.hwnd,eax
				mov		tmr2.hwnd,eax
			.endif
			.if fSelState==2
				mov		eax,pt.y
				.if sdword ptr eax<0
					xor		eax,eax
				.elseif eax>[esi].RAEDT.rc.bottom
					mov		eax,[esi].RAEDT.rc.bottom
				.endif
				add		eax,[esi].RAEDT.cpy
				mov		ecx,[ebx].EDIT.fntinfo.fntht
				.if sdword ptr eax<0
					neg		eax
					xor		edx,edx
					div		ecx
					mul		ecx
					neg		eax
				.else
					xor		edx,edx
					div		ecx
					mul		ecx
				.endif
				sub		eax,[esi].RAEDT.cpy
				mov		edi,eax
				mov		eax,pt.x
				.if sdword ptr eax<0
					xor		eax,eax
				.elseif eax>[esi].RAEDT.rc.right
					mov		eax,[esi].RAEDT.rc.right
				.endif
				push	eax
				invoke SetCpxMax,ebx,hWin
				pop		eax
				invoke GetCharFromPos,ebx,[esi].RAEDT.cpy,eax,edi
				push	eax
				.if eax
					dec		eax
					invoke IsCharLeadByte,ebx,eax
				.endif
				pop		edx
				add		edx,eax
				mov		eax,edx
				.if eax!=[ebx].EDIT.cpMin
					push	[ebx].EDIT.cpMin
					pop		cpOldMin
					mov		[ebx].EDIT.cpMin,eax
					.if ![ebx].EDIT.fCaretHide
						invoke HideCaret,hWin
						mov		[ebx].EDIT.fCaretHide,TRUE
					.endif
					invoke InvalidateSelection,ebx,[ebx].EDIT.edta.hwnd,cpOldMin,[ebx].EDIT.cpMin
					invoke InvalidateSelection,ebx,[ebx].EDIT.edtb.hwnd,cpOldMin,[ebx].EDIT.cpMin
					invoke SelChange,ebx,SEL_TEXT
				.endif
			.else
				;Block Selection, not on selbar
				mov		fShift,TRUE
				xor		eax,eax
				call	NestedProc_SetBlock
				invoke SelChange,ebx,SEL_TEXT
			.endif
		.elseif fOnSel==2
			mov		eax,pt.x
			sub		eax,ptDrag.x
			.if sdword ptr eax<0
				neg		eax
			.endif
			mov		edx,pt.y
			sub		edx,ptDrag.y
			.if sdword ptr edx<0
				neg		edx
			.endif
			.if eax>3 || edx>3
				mov		fOnSel,0
				mov		peff,0
				invoke LoadCursor,0,IDC_ARROW
				invoke SetCursor,eax
				mov		hDragSourceMem,ebx
				mov		eax,hWin
				mov		hDragWin,eax
				mov		eax,[ebx].EDIT.cpMin
				mov		edx,[ebx].EDIT.cpMax
				.if eax>edx
					xchg	eax,edx
				.endif
				mov		cpDragSource.cpMin,eax
				mov		cpDragSource.cpMax,edx
				invoke DoDragDrop,offset pIDataObject,offset pIDropSource,DROPEFFECT_COPY or DROPEFFECT_MOVE,offset peff
				mov		eax,peff
				.if eax==DROPEFFECT_MOVE && !([ebx].EDIT.fstyle & STYLE_READONLY)
					invoke IsSelectionLocked,ebx,cpDragSource.cpMin,cpDragSource.cpMax
					.if !eax
						mov		eax,[ebx].EDIT.cpMin
						.if eax>[ebx].EDIT.cpMax
							mov		eax,[ebx].EDIT.cpMax
						.endif
						push	eax
						invoke DeleteSelection,ebx,cpDragSource.cpMin,cpDragSource.cpMax
						pop		eax
						.if eax>cpDragSource.cpMin
							sub		eax,cpDragSource.cpMax
							add		eax,cpDragSource.cpMin
						.endif
						mov		[ebx].EDIT.cpMin,eax
						mov		[ebx].EDIT.cpMax,eax
						invoke GetCharPtr,ebx,[ebx].EDIT.cpMin
						invoke SetCaretVisible,hWin,[esi].RAEDT.cpy
						invoke SetCaret,ebx,[esi].RAEDT.cpy
						invoke InvalidateEdit,ebx,[ebx].EDIT.edta.hwnd
						invoke InvalidateEdit,ebx,[ebx].EDIT.edtb.hwnd
						invoke SetCpxMax,ebx,hWin
						invoke SelChange,ebx,SEL_TEXT
					.endif
				.endif
				invoke GetFocus
				.if eax==[ebx].EDIT.edta.hwnd || eax==[ebx].EDIT.edtb.hwnd
					invoke SetCaret,ebx,[esi].RAEDT.cpy
					invoke SetCaretVisible,hWin,[esi].RAEDT.cpy
				.endif
				mov		hDragSourceMem,0
			.endif
		.else
			mov		fOnBM,FALSE
			mov		fOnSel,0
			mov		ecx,[ebx].EDIT.selbarwt
			add		ecx,[ebx].EDIT.linenrwt
			mov		eax,pt.x
			.if sdword ptr eax<=ecx || fSelState
				;Selection on selbar
				mov		eax,hSelCur
				mov		hCur,eax
				mov		eax,pt.y
				.if sdword ptr eax>[esi].RAEDT.rc.bottom
					mov		eax,[esi].RAEDT.rc.bottom
				.elseif sdword ptr eax<0
					xor		eax,eax
				.endif
				.if fSelState
					push	[ebx].EDIT.cpMin
					pop		cpOldMin
					push	[ebx].EDIT.cpMax
					pop		cpOldMax
					add		eax,[esi].RAEDT.cpy
					mov		edx,4
					.if fShift
						mov		edx,eax
						sub		edx,iYp
						.if sdword ptr edx<0
							neg		edx
						.endif
					.endif
					.if edx>3
						.if eax>=iYp
							mov		edi,eax
							invoke GetCharFromPos,ebx,0,0,iYp
							mov		[ebx].EDIT.cpMin,eax
							invoke GetCharFromPos,ebx,0,0,edi
							mov		[ebx].EDIT.cpMax,eax
							add		edi,[ebx].EDIT.fntinfo.fntht
							invoke GetCharFromPos,ebx,0,0,edi
							.if eax==[ebx].EDIT.cpMax
								invoke GetCharFromPos,ebx,0,9999,edi
							.endif
							mov		[ebx].EDIT.cpMax,eax
						.else
							push	eax
							mov		eax,iYp
							add		eax,[ebx].EDIT.fntinfo.fntht
							invoke GetCharFromPos,ebx,0,0,eax
							mov		[ebx].EDIT.cpMax,eax
							pop		eax
							invoke GetCharFromPos,ebx,0,0,eax
							mov		[ebx].EDIT.cpMin,eax
						.endif
					.endif
					invoke SetCaret,ebx,[esi].RAEDT.cpy
					mov		eax,[ebx].EDIT.cpMin
					.if eax!=cpOldMin
						invoke InvalidateSelection,ebx,[ebx].EDIT.edta.hwnd,cpOldMin,[ebx].EDIT.cpMin
						invoke InvalidateSelection,ebx,[ebx].EDIT.edtb.hwnd,cpOldMin,[ebx].EDIT.cpMin
					.endif
					mov		eax,[ebx].EDIT.cpMax
					.if eax!=cpOldMax
						invoke InvalidateSelection,ebx,[ebx].EDIT.edta.hwnd,cpOldMax,[ebx].EDIT.cpMax
						invoke InvalidateSelection,ebx,[ebx].EDIT.edtb.hwnd,cpOldMax,[ebx].EDIT.cpMax
					.endif
					invoke SelChange,ebx,SEL_TEXT
					.if wParam&MK_LBUTTON
						mov		eax,pt.y
						.if eax>[esi].RAEDT.rc.bottom
							.if !tmr1.hwnd
								mov		eax,pt.y
								.if sdword ptr eax>[esi].RAEDT.rc.bottom
									mov		edx,eax
									sub		edx,[esi].RAEDT.rc.bottom
									mov		eax,hWin
									mov		tmr1.hwnd,eax
									mov		tmr1.umsg,WM_VSCROLL
									mov		tmr1.wparam,SB_LINEDOWN
									mov		eax,[esi].RAEDT.hvscroll
									mov		tmr1.lparam,eax
								.elseif sdword ptr eax<0
									mov		edx,eax
									neg		edx
									mov		eax,hWin
									mov		tmr1.hwnd,eax
									mov		tmr1.umsg,WM_VSCROLL
									mov		tmr1.wparam,SB_LINEUP
									mov		eax,[esi].RAEDT.hvscroll
									mov		tmr1.lparam,eax
								.endif
								mov		eax,hWin
								mov		tmr2.hwnd,eax
								mov		eax,uMsg
								mov		tmr2.umsg,eax
								mov		eax,wParam
								mov		tmr2.wparam,eax
								mov		eax,lParam
								mov		tmr2.lparam,eax
								shl		edx,2
								mov		eax,100
								sub		eax,edx
								.if sdword ptr eax<10
									mov		eax,10
								.endif
								invoke SetTimer,NULL,0,eax,offset TimerProc
								mov		TimerID,eax
							.endif
						.endif
					.endif
				.else
					mov		edx,[ebx].EDIT.cpx
					neg		edx
					invoke GetCharFromPos,ebx,[esi].RAEDT.cpy,edx,eax
					mov		cp,eax
					invoke GetCharPtr,ebx,eax
					mov		edi,[ebx].EDIT.rpChars
					add		edi,[ebx].EDIT.hChars
					mov		ecx,[edi].CHARS.len
					.if [edi].CHARS.state&STATE_BMMASK
						invoke GetPosFromChar,ebx,cp,addr pt
						mov		edx,pt.y
						sub		edx,[esi].RAEDT.cpy
						mov		eax,lParam
						shr		eax,16
						cwde
						sub		eax,edx
						mov		edx,[ebx].EDIT.fntinfo.fntht
						sub		edx,7
						shr		edx,1
						sub		eax,edx
						.if eax<12
							mov		eax,lParam
							and		eax,0FFFFh
							cwde
							sub		eax,[ebx].EDIT.linenrwt
							sub		eax,[ebx].EDIT.selbarwt
							add		eax,15
							.if eax<12
								invoke LoadCursor,0,IDC_ARROW
								mov		hCur,eax
								mov		fOnBM,TRUE
							.endif
						.endif
					.endif
				.endif
			.else
				invoke LoadCursor,0,IDC_IBEAM
				mov		hCur,eax
				mov		eax,[ebx].EDIT.cpMin
				.if eax!=[ebx].EDIT.cpMax
					invoke GetCharFromPos,ebx,[esi].RAEDT.cpy,pt.x,pt.y
					mov		cp,eax
					mov		ecx,[ebx].EDIT.cpMin
					mov		edx,[ebx].EDIT.cpMax
					.if ecx>edx
						xchg	ecx,edx
					.endif
					.if eax>=ecx && eax<edx
						invoke GetChar,ebx,cp
						.if eax!=0Dh
							;On selection
							mov		fOnSel,1
							invoke LoadCursor,0,IDC_ARROW
							mov		hCur,eax
						.endif
					.endif
				.endif
			.endif
			invoke SetCursor,hCur
		.endif
		xor		eax,eax
		ret
	.elseif eax==WM_LBUTTONDOWN
		.if !fOnSel
			mov		eax,wParam
			and		eax,MK_SHIFT
			mov		fShift,eax
			mov		eax,[ebx].EDIT.cpMax
			sub		eax,[ebx].EDIT.cpMin
			mov		fSel,eax
			;Get mouse x position
			mov		eax,lParam
			mov		edx,eax
			shr		edx,16
			mov		ptDrag.y,edx
			cwde
			mov		ptDrag.x,eax
			mov		ecx,[ebx].EDIT.selbarwt
			add		ecx,[ebx].EDIT.linenrwt
			.if eax<=ecx
				;On selection bar
				invoke GetTopFromYp,ebx,hWin,[esi].RAEDT.cpy
				invoke SetCapture,hWin
				.if !fOnBM
					.if !([ebx].EDIT.nMode&MODE_BLOCK)
						.if [ebx].EDIT.cpx
							mov		[ebx].EDIT.cpx,0
							invoke InvalidateEdit,ebx,[ebx].EDIT.edta.hwnd
							invoke InvalidateEdit,ebx,[ebx].EDIT.edtb.hwnd
						.endif
						mov		edx,lParam
						shr		edx,16
						add		edx,[esi].RAEDT.cpy
						mov		iYp,edx
						mov		fSelState,3
						.if fShift
							.if [ebx].EDIT.cpselbar==-1
								mov		eax,[ebx].EDIT.cpMin
								mov		[ebx].EDIT.cpselbar,eax
							.endif
							invoke GetCharFromPos,ebx,0,0,iYp
							mov		[ebx].EDIT.cpMin,eax
							invoke GetCharFromPos,ebx,0,9999,iYp
							mov		[ebx].EDIT.cpMax,eax
							mov		eax,iYp
							add		eax,[ebx].EDIT.fntinfo.fntht
							invoke GetCharFromPos,ebx,0,0,eax
							.if eax>[ebx].EDIT.cpMax
								mov		[ebx].EDIT.cpMax,eax
							.endif
							mov		eax,[ebx].EDIT.cpselbar
							invoke SendMessage,[ebx].EDIT.hwnd,EM_EXLINEFROMCHAR,0,[ebx].EDIT.cpselbar
							mov		nOldLine,eax
							invoke SendMessage,[ebx].EDIT.hwnd,EM_LINEINDEX,eax,0
							.if eax<[ebx].EDIT.cpMax
								mov		[ebx].EDIT.cpMin,eax
							.else
								mov		eax,[ebx].EDIT.cpMin
								mov		[ebx].EDIT.cpMax,eax
								inc		nOldLine
								invoke SendMessage,[ebx].EDIT.hwnd,EM_LINEINDEX,nOldLine,0
								mov		[ebx].EDIT.cpMin,eax
							.endif
							invoke InvalidateEdit,ebx,[ebx].EDIT.edta.hwnd
							invoke InvalidateEdit,ebx,[ebx].EDIT.edtb.hwnd
						.else
							invoke SendMessage,hWin,WM_MOUSEMOVE,wParam,lParam
							mov		[ebx].EDIT.cpselbar,-1
						.endif
					.endif
				.else
					;On bookmark
					invoke SetFocus,hWin
					mov		eax,[ebx].EDIT.cpx
					neg		eax
					mov		edx,lParam
					shr		edx,16
					invoke GetCharFromPos,ebx,[esi].RAEDT.cpy,eax,edx
					.if fSel
						push	eax
						invoke InvalidateSelection,ebx,[ebx].EDIT.edta.hwnd,[ebx].EDIT.cpMin,[ebx].EDIT.cpMax
						invoke InvalidateSelection,ebx,[ebx].EDIT.edtb.hwnd,[ebx].EDIT.cpMin,[ebx].EDIT.cpMax
						pop		eax
					.endif
					mov		[ebx].EDIT.cpMin,eax
					mov		[ebx].EDIT.cpMax,eax
					invoke GetCharPtr,ebx,eax
					invoke LoadCursor,0,IDC_ARROW
					invoke SetCursor,eax
					invoke SetCaretVisible,[esi].RAEDT.hwnd,[esi].RAEDT.cpy
					invoke SelChange,ebx,SEL_OBJECT
					invoke SetCaret,ebx,[esi].RAEDT.cpy
					invoke InvalidateSelection,ebx,[ebx].EDIT.edta.hwnd,[ebx].EDIT.cpMin,[ebx].EDIT.cpMax
					invoke InvalidateSelection,ebx,[ebx].EDIT.edtb.hwnd,[ebx].EDIT.cpMin,[ebx].EDIT.cpMax
				.endif
			.else
				mov		[ebx].EDIT.cpselbar,-1
				.if !([ebx].EDIT.nMode&MODE_BLOCK)
					.if fSel
						invoke InvalidateSelection,ebx,[ebx].EDIT.edta.hwnd,[ebx].EDIT.cpMin,[ebx].EDIT.cpMax
						invoke InvalidateSelection,ebx,[ebx].EDIT.edtb.hwnd,[ebx].EDIT.cpMin,[ebx].EDIT.cpMax
					.endif
					mov		eax,lParam
					mov		edx,eax
					cwde
					shr		edx,16
					add		eax,[ebx].EDIT.cpx
					mov		[esi].RAEDT.cpxmax,eax
					sub		eax,[ebx].EDIT.cpx
					invoke GetCharFromPos,ebx,[esi].RAEDT.cpy,eax,edx
					push	eax
					dec		eax
					invoke IsCharLeadByte,ebx,eax
					pop		edx
					add		edx,eax
					mov		eax,edx
					mov		[ebx].EDIT.cpMin,eax
					.if !fShift
						mov		[ebx].EDIT.cpMax,eax
					.endif
					invoke SetFocus,hWin
					invoke SendMessage,hWin,WM_SETFOCUS,0,0
					invoke SetCaretVisible,hWin,[esi].RAEDT.cpy
					.if fShift
						invoke InvalidateSelection,ebx,[ebx].EDIT.edta.hwnd,[ebx].EDIT.cpMin,[ebx].EDIT.cpMax
						invoke InvalidateSelection,ebx,[ebx].EDIT.edtb.hwnd,[ebx].EDIT.cpMin,[ebx].EDIT.cpMax
					.endif
					invoke SetCapture,hWin
					mov		fSelState,1
				.else
					mov		fSelState,10
					invoke GetCursorPos,addr pt
					invoke ScreenToClient,hWin,addr pt
					call	NestedProc_SetBlock
					invoke SetCapture,hWin
					invoke SetFocus,hWin
				.endif
				invoke SetCpxMax,ebx,hWin
				invoke SelChange,ebx,SEL_TEXT
			.endif
		.elseif [ebx].EDIT.fstyle & STYLE_DRAGDROP
			invoke GetCursorPos,addr ptDrag
			invoke ScreenToClient,hWin,addr ptDrag
			mov		fOnSel,2
			invoke LoadCursor,0,IDC_ARROW
			invoke SetCursor,eax
		.endif
		xor		eax,eax
		ret
	.elseif eax==WM_LBUTTONUP
		.if fOnBM
			invoke LoadCursor,0,IDC_ARROW
			invoke SetCursor,eax
		.elseif fOnSel==1
			invoke LoadCursor,0,IDC_ARROW
			invoke SetCursor,eax
		.elseif fOnSel==2
			mov		fOnSel,0
			invoke SendMessage,hWin,WM_LBUTTONDOWN,wParam,lParam
		.endif
		invoke ReleaseCapture
		invoke SetCaret,ebx,[esi].RAEDT.cpy
		inc		nUndoid
		xor		eax,eax
		mov		fSelState,eax
		ret
	.elseif eax==WM_LBUTTONDBLCLK
		mov		eax,[ebx].EDIT.fstyle
		and		eax,STYLE_NODBLCLICK
		mov		edx,[ebx].EDIT.nMode
		and		edx,MODE_BLOCK
		.if fOnBM
			invoke LoadCursor,0,IDC_ARROW
			invoke SetCursor,eax
			invoke SetCaretVisible,[esi].RAEDT.hwnd,[esi].RAEDT.cpy
			invoke SelChange,ebx,SEL_OBJECT
		.elseif !eax && !edx
			mov		eax,[ebx].EDIT.cpMin
			mov		cpOldMin,eax
			mov		edx,[ebx].EDIT.cpMax
			mov		cpOldMax,edx
			mov		eax,lParam
			mov		edx,eax
			cwde
			shr		edx,16
			add		eax,[ebx].EDIT.cpx
			mov		[esi].RAEDT.cpxmax,eax
			sub		eax,[ebx].EDIT.cpx
			invoke GetCharFromPos,ebx,[esi].RAEDT.cpy,eax,edx
			push	eax
			dec		eax
			invoke IsCharLeadByte,ebx,eax
			pop		edx
			add		edx,eax
			mov		eax,edx
			mov		[ebx].EDIT.cpMin,eax
			mov		[ebx].EDIT.cpMax,eax
			invoke InvalidateSelection,ebx,[ebx].EDIT.edta.hwnd,cpOldMin,cpOldMax
			invoke InvalidateSelection,ebx,[ebx].EDIT.edtb.hwnd,cpOldMin,cpOldMax
			invoke GetWordStart,ebx,[ebx].EDIT.cpMin,0
			mov		[ebx].EDIT.cpMin,eax
			invoke GetWordEnd,ebx,eax,0
			mov		[ebx].EDIT.cpMax,eax
			invoke InvalidateSelection,ebx,[ebx].EDIT.edta.hwnd,[ebx].EDIT.cpMin,[ebx].EDIT.cpMax
			invoke InvalidateSelection,ebx,[ebx].EDIT.edtb.hwnd,[ebx].EDIT.cpMin,[ebx].EDIT.cpMax
			invoke SelChange,ebx,SEL_TEXT
			mov		eax,[ebx].EDIT.cpMin
			.if eax!=[ebx].EDIT.cpMax
				invoke LoadCursor,0,IDC_ARROW
				invoke SetCursor,eax
				mov		fOnSel,1
			.endif
		.else
			invoke ReleaseCapture
			invoke SendMessage,[ebx].EDIT.hwnd,uMsg,wParam,lParam
		.endif
		inc		nUndoid
		xor		eax,eax
		ret
	.elseif eax==WM_RBUTTONDOWN
		mov		eax,[ebx].EDIT.cpMin
		.if eax==[ebx].EDIT.cpMax
			invoke SendMessage,hWin,WM_LBUTTONDOWN,wParam,lParam
			invoke SendMessage,hWin,WM_LBUTTONUP,wParam,lParam
		.endif
		invoke GetParent,hWin
		invoke GetParent,eax
		invoke SetFocus,eax
		invoke SetFocus,hWin
		xor		eax,eax
		ret
	.elseif eax==WM_MOUSEWHEEL
		mov		eax,wParam
		and		eax,MK_CONTROL or MK_SHIFT
		.if [ebx].EDIT.nScroll
			.if !eax
				push	[esi].RAEDT.cpy
				mov		sinf.cbSize,sizeof sinf
				mov		sinf.fMask,SIF_ALL
				invoke GetScrollInfo,[esi].RAEDT.hvscroll,SB_CTL,addr sinf
				mov		eax,[ebx].EDIT.nScroll
				mov		edx,[ebx].EDIT.fntinfo.fntht
				mul		edx
				mov		edx,eax
				mov		eax,wParam
				.if sdword ptr eax>0
					.if [esi].RAEDT.cpy>edx
						sub		[esi].RAEDT.cpy,edx
					.else
						mov		[esi].RAEDT.cpy,0
					.endif
				.else
					mov		eax,sinf.nMax
					.if eax<sinf.nPage
						jmp		@f
					.endif
					sub		eax,sinf.nPage
					add		[esi].RAEDT.cpy,edx
					.if sdword ptr eax>[esi].RAEDT.cpy
						jmp		@f
					.endif
					mov		[esi].RAEDT.cpy,eax
				  @@:
				.endif
				pop		eax
				sub		eax,[esi].RAEDT.cpy
				.if eax
					push	eax
					invoke SetCaret,ebx,[esi].RAEDT.cpy
					pop		eax
					invoke ScrollEdit,ebx,hWin,0,eax
				.endif
			.elseif eax==MK_CONTROL or MK_SHIFT
				mov		eax,wParam
				.if sdword ptr eax>0
					mov		eax,SB_LINELEFT
				.else
					mov		eax,SB_LINERIGHT
				.endif
				mov		ecx,[ebx].EDIT.nScroll
				.while ecx
					push	eax

					push	ecx
					invoke PostMessage,[ebx].EDIT.hwnd,WM_HSCROLL,eax,[ebx].EDIT.hhscroll
					pop		ecx
					pop		eax
					dec		ecx
				.endw
			.endif
		.endif
		xor		eax,eax
		ret
	.elseif eax==WM_VSCROLL
		push	[esi].RAEDT.cpy
		mov		sinf.cbSize,sizeof sinf
		mov		sinf.fMask,SIF_ALL
		invoke GetScrollInfo,lParam,SB_CTL,addr sinf
		mov		eax,wParam
		movzx	eax,ax
		.if eax==SB_THUMBTRACK || eax==SB_THUMBPOSITION
			mov		eax,sinf.nTrackPos
			mov		[esi].RAEDT.cpy,eax
		.elseif eax==SB_LINEDOWN
			mov		eax,sinf.nMax
			sub		eax,sinf.nPage
			.if sdword ptr eax>[esi].RAEDT.cpy
				mov		eax,[esi].RAEDT.cpy
				mov		ecx,[ebx].EDIT.fntinfo.fntht
				xor		edx,edx
				div		ecx
				mul		ecx
				add		eax,ecx
				mov		[esi].RAEDT.cpy,eax
			.endif
		.elseif eax==SB_LINEUP
			.if [esi].RAEDT.cpy
				mov		eax,[esi].RAEDT.cpy
				mov		ecx,[ebx].EDIT.fntinfo.fntht
				xor		edx,edx
				div		ecx
				mul		ecx
				.if eax>ecx
					sub		eax,ecx
				.else
					xor		eax,eax
				.endif
				mov		[esi].RAEDT.cpy,eax
			.endif
		.elseif eax==SB_PAGEDOWN
			mov		eax,sinf.nPage
			add		[esi].RAEDT.cpy,eax
			mov		eax,sinf.nMax
			sub		eax,sinf.nPage
			.if eax<[esi].RAEDT.cpy
				mov		[esi].RAEDT.cpy,eax
			.endif
		.elseif eax==SB_PAGEUP
			mov		eax,sinf.nPage
			.if [esi].RAEDT.cpy>eax
				sub		[esi].RAEDT.cpy,eax
			.else
				mov		[esi].RAEDT.cpy,0
			.endif
		.elseif eax==SB_TOP
			mov		[esi].RAEDT.cpy,0
		.elseif eax==SB_BOTTOM
			mov		eax,sinf.nMax
			sub		eax,sinf.nPage
			mov		[esi].RAEDT.cpy,eax
		.endif
		pop		edx
		sub		edx,[esi].RAEDT.cpy
		.if edx!=0
			invoke ScrollEdit,ebx,hWin,0,edx
		.endif
		.if [ebx].EDIT.fstyle&STYLE_SCROLLTIP
			mov		eax,wParam
			movzx	eax,ax
			.if eax==SB_THUMBTRACK
				invoke GetCursorPos,addr pt
				add		pt.y,15
				mov		eax,pt.y
				.if eax!=MpY
					mov		MpY,eax
					.if fTlln==FALSE
						mov		eax,pt.x
						sub		eax,60
						mov		MpX,eax
						mov		fTlln,TRUE
					.endif
					invoke MoveWindow,[ebx].EDIT.htlt,MpX,pt.y,60,15,TRUE
					;Get the top line number
					mov		eax,[esi].RAEDT.topln
					inc		eax
					invoke DwToAscii,eax,addr szLine+4
					invoke SetWindowText,[ebx].EDIT.htlt,addr szLine
					invoke ShowWindow,[ebx].EDIT.htlt,SW_SHOWNOACTIVATE
					invoke InvalidateRect,[ebx].EDIT.htlt,NULL,TRUE
					invoke UpdateWindow,[ebx].EDIT.htlt
				.endif
			.elseif eax==SB_ENDSCROLL
				mov		MpY,0
				mov		fTlln,FALSE
				invoke ShowWindow,[ebx].EDIT.htlt,SW_HIDE
			.endif
		.endif
		xor		eax,eax
		ret
	.elseif eax==WM_HSCROLL
		invoke PostMessage,[ebx].EDIT.hwnd,uMsg,wParam,lParam
		xor		eax,eax
		ret
	.elseif eax==WM_SETFOCUS
		invoke DefWindowProc,hWin,uMsg,wParam,lParam
		mov		eax,hWin
		mov		[ebx].EDIT.focus,eax
		.if !([ebx].EDIT.nMode&MODE_BLOCK)
			mov		eax,2
		.else
			mov		eax,3
		.endif
		mov		edx,[ebx].EDIT.fntinfo.fntht
		invoke CreateCaret,hWin,NULL,eax,edx
		invoke SetCaret,ebx,[esi].RAEDT.cpy
		invoke SelChange,ebx,SEL_TEXT
		xor		eax,eax
		jmp		Ex
	.elseif eax==WM_KILLFOCUS
		invoke DestroyCaret
	.elseif eax==WM_CREATE
		invoke GetParent,hWin
		invoke GetWindowLong,eax,0
		invoke SetWindowLong,hWin,0,eax
	.elseif eax==WM_WINDOWPOSCHANGED
		mov		fSize,TRUE
		mov		eax,[ebx].EDIT.edta.hwnd
		.if eax==hWin
			invoke GetClientRect,hWin,addr [ebx].EDIT.edta.rc
			mov		eax,[ebx].EDIT.fstyle
			and		eax,STYLE_NOSPLITT or STYLE_NOVSCROLL
			.if eax!=STYLE_NOSPLITT or STYLE_NOVSCROLL
				mov		eax,SBWT
				sub		[ebx].EDIT.edta.rc.right,eax
				invoke MoveWindow,[ebx].EDIT.edta.hvscroll,[ebx].EDIT.edta.rc.right,0,SBWT,[ebx].EDIT.edta.rc.bottom,TRUE
			.else
				invoke MoveWindow,[ebx].EDIT.edta.hvscroll,0,0,0,0,TRUE
			.endif
		.else
			invoke GetClientRect,hWin,addr [ebx].EDIT.edtb.rc
			mov		eax,[ebx].EDIT.fstyle
			and		eax,STYLE_NOSPLITT or STYLE_NOVSCROLL
			.if eax!=STYLE_NOSPLITT or STYLE_NOVSCROLL
				mov		eax,SBWT
				sub		[ebx].EDIT.edtb.rc.right,eax
				mov		ecx,[ebx].EDIT.edtb.rc.bottom
				xor		edx,edx
				.if ![ebx].EDIT.nsplitt
					.if !([ebx].EDIT.fstyle&STYLE_NOSPLITT)
						mov		edx,BTNHT
						sub		ecx,edx
					.endif
				.endif
				invoke MoveWindow,[ebx].EDIT.edtb.hvscroll,[ebx].EDIT.edtb.rc.right,edx,SBWT,ecx,TRUE
			.else
				invoke MoveWindow,[ebx].EDIT.edtb.hvscroll,0,0,0,0,TRUE
			.endif
		.endif
		invoke SetCaret,ebx,[esi].RAEDT.cpy
		xor		eax,eax
		jmp		Ex
	.elseif eax==WM_GETDLGCODE
 		mov		eax,DLGC_WANTCHARS or DLGC_WANTALLKEYS
		jmp		Ex
	.elseif eax==WM_SETCURSOR
		xor		eax,eax
		jmp		Ex
	.endif
  ExDef:
	invoke DefWindowProc,hWin,uMsg,wParam,lParam
  Ex:
	ret

NestedProc_SetBlock:
	invoke GetBlockRects,ebx,addr oldrects
	mov		eax,pt.y
	.if sdword ptr eax<0
		xor		eax,eax
	.elseif eax>[esi].RAEDT.rc.bottom
		mov		eax,[esi].RAEDT.rc.bottom
	.endif
	add		eax,[esi].RAEDT.cpy
	invoke GetLineFromYp,ebx,eax
	mov		[ebx].EDIT.blrg.lnMin,eax
	.if !fShift
		mov		[ebx].EDIT.blrg.lnMax,eax
	.endif
	mov		edx,[ebx].EDIT.linenrwt
	add		edx,[ebx].EDIT.selbarwt
	mov		eax,pt.x
	.if sdword ptr eax<edx
		mov		eax,edx
	.elseif eax>[esi].RAEDT.rc.right
		mov		eax,[esi].RAEDT.rc.right
	.endif
	sub		eax,[ebx].EDIT.linenrwt
	sub		eax,[ebx].EDIT.selbarwt
	add		eax,[ebx].EDIT.cpx
	mov		ecx,[ebx].EDIT.fntinfo.fntwt
	cdq
	idiv	ecx
	mov		[ebx].EDIT.blrg.clMin,eax
	.if !fShift
		mov		[ebx].EDIT.blrg.clMax,eax
	.endif
	invoke GetBlockCp,ebx,[ebx].EDIT.blrg.lnMin,[ebx].EDIT.blrg.clMin
	mov		[ebx].EDIT.cpMin,eax
	mov		[ebx].EDIT.cpMax,eax
	invoke SetCaret,ebx,[esi].RAEDT.cpy
	invoke InvalidateBlock,ebx,addr oldrects
	retn

ErrBeep:
	invoke MessageBeep,MB_ICONHAND
	xor		eax,eax
	ret

NestedProc_SetScroll:
	mov		sinf.cbSize,sizeof sinf
	mov		sinf.fMask,SIF_ALL
	mov		sinf.nMin,0
	mov		eax,[ebx].EDIT.rpLineFree
	shr		eax,2
	sub		eax,[ebx].EDIT.nHidden
	mov		ecx,[ebx].EDIT.fntinfo.fntht
	mul		ecx
	.if eax<[esi].RAEDT.rc.bottom
		mov		eax,[esi].RAEDT.rc.bottom
		xor		edx,edx
		div		ecx
		mul		ecx
	.endif
	mov		sinf.nMax,eax
	mov		eax,[esi].RAEDT.rc.bottom
	xor		edx,edx
	div		ecx
	mul		ecx
	mov		sinf.nPage,eax
	mov		eax,[esi].RAEDT.cpy
	mov		sinf.nPos,eax
	invoke SetScrollInfo,[esi].RAEDT.hvscroll,SB_CTL,addr sinf,TRUE
	mov		eax,[ebx].EDIT.fntinfo.fntwt
	shl		eax,4
	mov		sinf.nPage,eax
	shl		eax,5
	mov		sinf.nMax,eax
	mov		eax,[ebx].EDIT.cpx
	mov		sinf.nPos,eax
	invoke SetScrollInfo,[ebx].EDIT.hhscroll,SB_CTL,addr sinf,TRUE
	retn

RAEditProc endp

GetText proc uses ebx esi edi,hMem:DWORD,cpMin:DWORD,cpMax:DWORD,lpText:DWORD,fLf:DWORD
	LOCAL	nLf:DWORD

	mov		nLf,0
	mov		ebx,hMem
	mov		eax,cpMin
	mov		edx,cpMax
	mov		edi,lpText
	.if eax>edx
		xchg	eax,edx
	.endif
	mov		cpMin,eax
	mov		cpMax,edx
	invoke GetCharPtr,ebx,cpMax
	mov		cpMax,ecx
	invoke GetCharPtr,ebx,cpMin
	mov		cpMin,ecx
	mov		ecx,eax
	mov		edx,cpMin
	mov		esi,[ebx].EDIT.hLine
	add		esi,[ebx].EDIT.rpLine
	.while edx<cpMax
		mov		eax,[ebx].EDIT.hChars
		add		eax,[esi].LINE.rpChars
		push	eax
		mov		al,[eax+ecx+sizeof CHARS]
		inc		ecx
		.if edi
			mov		[edi],al
			inc		edi
		.endif
		.if fLf && al==0Dh
			.if edi
				mov		al,0Ah
				mov		[edi],al
				inc		edi
			.endif
			inc		nLf
		.endif
		pop		eax
		.if ecx==[eax].CHARS.len
			xor		ecx,ecx
			add		esi,sizeof LINE
		.endif
		inc		edx
	.endw
	.if edi
		mov		byte ptr [edi],0
	.endif
	mov		eax,cpMax
	sub		eax,cpMin
	ret

GetText endp

FakeToolTipProc proc hWin:HWND,uMsg:UINT,wParam:WPARAM,lParam:LPARAM
	LOCAL	ps:PAINTSTRUCT
	LOCAL	buffer[16]:BYTE
	LOCAL	hFnt:DWORD

	mov		eax,uMsg
	.if eax==WM_PAINT
		invoke SendMessage,hWin,WM_GETFONT,0,0
		mov		hFnt,eax
		invoke GetWindowText,hWin,addr buffer,sizeof buffer
		invoke BeginPaint,hWin,addr ps
		invoke SelectObject,ps.hdc,hFnt
		push	eax
		invoke SetBkMode,ps.hdc,TRANSPARENT
		invoke GetSysColor,COLOR_INFOTEXT
		invoke SetTextColor,ps.hdc,eax
		invoke FillRect,ps.hdc,addr ps.rcPaint,hBrTlt
		invoke strlen,addr buffer
		invoke TextOut,ps.hdc,5,0,addr buffer,eax
		pop		eax
		invoke SelectObject,ps.hdc,eax
		invoke EndPaint,hWin,addr ps
		xor		eax,eax
		ret
	.endif
	invoke CallWindowProc,OldFakeToolTipProc,hWin,uMsg,wParam,lParam
	ret

FakeToolTipProc endp

ConvTwipsToPixels proc hDC:HDC,fHorz:DWORD,lSize:DWORD

	.if fHorz
		invoke GetDeviceCaps,hDC,LOGPIXELSX
	.else
		invoke GetDeviceCaps,hDC,LOGPIXELSY
	.endif
	;	mov		ecx,lSize
	;	mul		ecx
	;	mov		ecx,1440
	;	div		ecx
	invoke MulDiv,lSize,1440,eax
	ret

ConvTwipsToPixels endp

;The edit controls callback (WndProc).
RAWndProc proc uses ebx esi edi,hWin:HWND,uMsg:UINT,wParam:WPARAM,lParam:LPARAM
	LOCAL	rect:RECT
	LOCAL	pt:POINT
	LOCAL	sinf:SCROLLINFO
	LOCAL	chrg:CHARRANGE
	LOCAL	ti:TOOLINFO
	LOCAL	oldrects[2]:RECT
	LOCAL	nLine:DWORD
	LOCAL	len:DWORD
	LOCAL	tabWt:DWORD
	LOCAL	lf:LOGFONT
	LOCAL	fAlt:DWORD
	LOCAL	fShift:DWORD
	LOCAL	fControl:DWORD

	;Get memory pointer
	invoke GetWindowLong,hWin,0
	.if eax
		mov		ebx,eax
		mov		eax,[ebx].EDIT.focus
		.if eax==[ebx].EDIT.edta.hwnd
			lea		esi,[ebx].EDIT.edta
		.else
			lea		esi,[ebx].EDIT.edtb
		.endif
	.else
		.if uMsg!=WM_CREATE
			jmp		ExDef
		.endif
	.endif
	mov		eax,uMsg
	.if eax>=REM_BASE && eax<=REM_GETLINEBEGIN
		sub		eax,REM_BASE
		jmp 	DWORD PTR [offset _REM_BASE+eax*4]
		; RAEdit_REM_Msg_JumpTable.asm
		;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
				align 4
		_REM_SETHILITEWORDS:
			;wParam=Color
			;lParam=lpszWords
			invoke SetHiliteWords,wParam,lParam
			xor		eax,eax
			ret
		align 4
		_REM_SETFONT:
			;wParam=nLineSpacing
			;lParam=lpRAFONT
			mov		ecx,[ebx].EDIT.fntinfo.fntht
			.if ecx
				mov		eax,[ebx].EDIT.edta.cpy
				xor		edx,edx
				div		ecx
				push	eax
				mov		eax,[ebx].EDIT.edtb.cpy
				xor		edx,edx
				div		ecx
				push	eax
			.else
				push	0 ; stack_temp_used -2
				push	0
			.endif
			mov		eax,wParam
			mov		[ebx].EDIT.fntinfo.linespace,eax
			invoke SetFont,ebx,lParam
			mov		ecx,[ebx].EDIT.fntinfo.fntht
			pop		eax
			mul		ecx
			mov		[ebx].EDIT.edtb.cpy,eax
			pop		eax
			mul		ecx
			mov		[ebx].EDIT.edta.cpy,eax
			xor		eax,eax
			mov		[ebx].EDIT.edta.topyp,eax
			mov		[ebx].EDIT.edta.topln,eax
			mov		[ebx].EDIT.edta.topcp,eax
			mov		[ebx].EDIT.edtb.topyp,eax
			mov		[ebx].EDIT.edtb.topln,eax
			mov		[ebx].EDIT.edtb.topcp,eax
			invoke InvalidateEdit,ebx,[ebx].EDIT.edta.hwnd
			invoke InvalidateEdit,ebx,[ebx].EDIT.edtb.hwnd
			.if ![ebx].EDIT.fntinfo.monospace
				mov		eax,[ebx].EDIT.nMode
				.if eax&MODE_BLOCK
					xor		eax,MODE_BLOCK
					invoke SendMessage,hWin,REM_SETMODE,eax,0
				.endif
			.endif
			invoke GetFocus
			.if eax==[ebx].EDIT.focus && eax
				invoke SetFocus,hWin
			.endif
			xor		eax,eax
			ret
		align 4
		_REM_GETFONT:
			;wParam=0
			;lParam=lpRAFONT
			mov		edx,lParam
			mov		eax,[ebx].EDIT.fnt.hFont
			mov		[edx].RAFONT.hFont,eax
			mov		eax,[ebx].EDIT.fnt.hIFont
			mov		[edx].RAFONT.hIFont,eax
			mov		eax,[ebx].EDIT.fnt.hLnrFont
			mov		[edx].RAFONT.hLnrFont,eax
			mov		eax,[ebx].EDIT.fntinfo.linespace
			ret
		align 4
		_REM_SETCOLOR:
			;wParam=0
			;lParam=lpRACOLOR
			mov		edx,lParam
			mov		eax,[edx].RACOLOR.bckcol
			mov		[ebx].EDIT.clr.bckcol,eax
			mov		eax,[edx].RACOLOR.txtcol
			mov		[ebx].EDIT.clr.txtcol,eax
			mov		eax,[edx].RACOLOR.selbckcol
			.if eax==[edx].RACOLOR.bckcol
				xor		eax,03F3F3Fh
			.endif
			mov		[ebx].EDIT.clr.selbckcol,eax
			mov		eax,[edx].RACOLOR.seltxtcol
			mov		[ebx].EDIT.clr.seltxtcol,eax
			mov		eax,[edx].RACOLOR.cmntcol
			mov		[ebx].EDIT.clr.cmntcol,eax
			mov		eax,[edx].RACOLOR.strcol
			mov		[ebx].EDIT.clr.strcol,eax
			mov		eax,[edx].RACOLOR.oprcol
			mov		[ebx].EDIT.clr.oprcol,eax
			mov		eax,[edx].RACOLOR.hicol1
			mov		[ebx].EDIT.clr.hicol1,eax
			mov		eax,[edx].RACOLOR.hicol2
			mov		[ebx].EDIT.clr.hicol2,eax
			mov		eax,[edx].RACOLOR.hicol3
			mov		[ebx].EDIT.clr.hicol3,eax
			mov		eax,[edx].RACOLOR.selbarbck
			mov		[ebx].EDIT.clr.selbarbck,eax
			mov		eax,[edx].RACOLOR.selbarpen
			mov		[ebx].EDIT.clr.selbarpen,eax
			mov		eax,[edx].RACOLOR.lnrcol
			mov		[ebx].EDIT.clr.lnrcol,eax
			mov		eax,[edx].RACOLOR.numcol
			mov		[ebx].EDIT.clr.numcol,eax
			mov		eax,[edx].RACOLOR.cmntback
			mov		[ebx].EDIT.clr.cmntback,eax
			mov		eax,[edx].RACOLOR.strback
			mov		[ebx].EDIT.clr.strback,eax
			mov		eax,[edx].RACOLOR.numback
			mov		[ebx].EDIT.clr.numback,eax
			mov		eax,[edx].RACOLOR.oprback
			mov		[ebx].EDIT.clr.oprback,eax
			mov		eax,[edx].RACOLOR.changed
			mov		[ebx].EDIT.clr.changed,eax
			mov		eax,[edx].RACOLOR.changesaved
			mov		[ebx].EDIT.clr.changesaved,eax
			invoke CreateBrushes,ebx
			invoke InvalidateEdit,ebx,[ebx].EDIT.edta.hwnd
			invoke InvalidateEdit,ebx,[ebx].EDIT.edtb.hwnd
			invoke InvalidateRect,[ebx].EDIT.hsta,NULL,FALSE
			xor		eax,eax
			ret
		align 4
		_REM_GETCOLOR:
			;wParam=0
			;lParam=lpRACOLOR
			mov		edx,lParam
			mov		eax,[ebx].EDIT.clr.bckcol
			mov		[edx].RACOLOR.bckcol,eax
			mov		eax,[ebx].EDIT.clr.txtcol
			mov		[edx].RACOLOR.txtcol,eax
			mov		eax,[ebx].EDIT.clr.selbckcol
			mov		[edx].RACOLOR.selbckcol,eax
			mov		eax,[ebx].EDIT.clr.seltxtcol
			mov		[edx].RACOLOR.seltxtcol,eax
			mov		eax,[ebx].EDIT.clr.cmntcol
			mov		[edx].RACOLOR.cmntcol,eax
			mov		eax,[ebx].EDIT.clr.strcol
			mov		[edx].RACOLOR.strcol,eax
			mov		eax,[ebx].EDIT.clr.oprcol
			mov		[edx].RACOLOR.oprcol,eax
			mov		eax,[ebx].EDIT.clr.hicol1
			mov		[edx].RACOLOR.hicol1,eax
			mov		eax,[ebx].EDIT.clr.hicol2
			mov		[edx].RACOLOR.hicol2,eax
			mov		eax,[ebx].EDIT.clr.hicol3
			mov		[edx].RACOLOR.hicol3,eax
			mov		eax,[ebx].EDIT.clr.selbarbck
			mov		[edx].RACOLOR.selbarbck,eax
			mov		eax,[ebx].EDIT.clr.selbarpen
			mov		[edx].RACOLOR.selbarpen,eax
			mov		eax,[ebx].EDIT.clr.lnrcol
			mov		[edx].RACOLOR.lnrcol,eax
			mov		eax,[ebx].EDIT.clr.numcol
			mov		[edx].RACOLOR.numcol,eax
			mov		eax,[ebx].EDIT.clr.cmntback
			mov		[edx].RACOLOR.cmntback,eax
			mov		eax,[ebx].EDIT.clr.strback
			mov		[edx].RACOLOR.strback,eax
			mov		eax,[ebx].EDIT.clr.numback
			mov		[edx].RACOLOR.numback,eax
			mov		eax,[ebx].EDIT.clr.oprback
			mov		[edx].RACOLOR.oprback,eax
			mov		eax,[ebx].EDIT.clr.changed
			mov		[edx].RACOLOR.changed,eax
			mov		eax,[ebx].EDIT.clr.changesaved
			mov		[edx].RACOLOR.changesaved,eax
			xor		eax,eax
			ret
		align 4
		_REM_SETHILITELINE:
			;wParam=Line
			;lParam=nColor
			invoke HiliteLine,ebx,wParam,lParam
			ret
		align 4
		_REM_GETHILITELINE:
			;wParam=Line
			;lParam=0
			xor		eax,eax
			dec		eax
			mov		edx,wParam
			shl		edx,2
			.if edx<[ebx].EDIT.rpLineFree
				add		edx,[ebx].EDIT.hLine
				mov		edx,[edx].LINE.rpChars
				add		edx,[ebx].EDIT.hChars
				mov		eax,[edx].CHARS.state
				and		eax,STATE_HILITEMASK
			.endif
			ret
		align 4
		_REM_SETBOOKMARK:
			;wParam=Line
			;lParam=nType
			invoke SetBookMark,ebx,wParam,lParam
			push	eax
			invoke InvalidateLine,ebx,[ebx].EDIT.edta.hwnd,wParam
			invoke InvalidateLine,ebx,[ebx].EDIT.edtb.hwnd,wParam
			pop		eax
			ret
		align 4
		_REM_GETBOOKMARK:
			;wParam=Line
			;lParam=0
			invoke GetBookMark,ebx,wParam
			ret
		align 4
		_REM_CLRBOOKMARKS:
			;wParam=0
			;lParam=nType
			invoke ClearBookMarks,ebx,lParam
			invoke InvalidateEdit,ebx,[ebx].EDIT.edta.hwnd
			invoke InvalidateEdit,ebx,[ebx].EDIT.edtb.hwnd
			xor		eax,eax
			ret
		align 4
		_REM_NXTBOOKMARK:
			;wParam=Line
			;lParam=nType
			invoke NextBookMark,ebx,wParam,lParam
			ret
		align 4
		_REM_PRVBOOKMARK:
			;wParam=Line
			;lParam=nType
			invoke PreviousBookMark,ebx,wParam,lParam
			ret
		align 4
		_REM_FINDBOOKMARK:
			;wParam=BmID
			;lParam=0
			xor		eax,eax
			dec		eax
			mov		ecx,wParam
			xor		edi,edi
			.while edi<[ebx].EDIT.rpLineFree
				mov		edx,edi
				add		edx,[ebx].EDIT.hLine
				mov		edx,[edx].LINE.rpChars
				add		edx,[ebx].EDIT.hChars
				.if ecx==[edx].CHARS.bmid
					mov		eax,edi
					shr		eax,2
					.break
				.endif
				add		edi,sizeof LINE
			.endw
			ret
		align 4
		_REM_SETBLOCKS:
			;wParam=[lpLINERANGE]
			;lParam=0
			push	nBmid
			mov		esi,offset blockdefs
			lea		edi,[esi+32*4]
			.while dword ptr [esi]
				mov		eax,[edi].RABLOCKDEF.flag
				shr		eax,16
				.if eax==[ebx].EDIT.nWordGroup
					invoke SetBlocks,ebx,wParam,edi
				.endif
				mov		edi,[esi]
				add		esi,4
			.endw
			pop		eax
			.if eax!=nBmid
				invoke InvalidateRect,[ebx].EDIT.edta.hwnd,NULL,FALSE
				invoke InvalidateRect,[ebx].EDIT.edtb.hwnd,NULL,FALSE
			.endif
			xor		eax,eax
			ret
		align 4
		_REM_ISLINE:
			;wParam=Line
			;lParam=lpszDef
			invoke IsLine,ebx,wParam,lParam
			ret
		align 4
		_REM_GETWORD:
			;wParam=BuffSize
			;lParam=lpBuff
			invoke GetWordStart,ebx,[ebx].EDIT.cpMin,0
			mov		esi,[ebx].EDIT.rpChars
			mov		ecx,eax
			sub		ecx,[ebx].EDIT.cpLine
			push	ecx
			push	eax
			invoke GetWordEnd,ebx,eax,0
			pop		ecx
			pop		edx
			sub		eax,ecx
			mov		ecx,eax
			mov		edi,lParam
			.if ecx>=wParam
				mov		ecx,wParam
				dec		ecx
			.endif
			add		esi,[ebx].EDIT.hChars
			add		esi,edx
			add		esi,sizeof CHARS
			mov		eax,ecx
			rep movsb
			mov		byte ptr [edi],0
			ret
		align 4
		_REM_COLLAPSE:
			;wParam=Line
			;lParam=0
			invoke Collapse,ebx,wParam
			invoke InvalidateEdit,ebx,[ebx].EDIT.edta.hwnd
			invoke InvalidateEdit,ebx,[ebx].EDIT.edtb.hwnd
			ret
		align 4
		_REM_COLLAPSEALL:
			;wParam=0
			;lParam=0
			invoke CollapseAll,ebx
			.if eax
				push	esi
				push	edi
				invoke GetLineFromCp,ebx,[ebx].EDIT.cpMin
				mov		esi,eax
				mov		edi,eax
			  @@:
				invoke IsLineHidden,ebx,esi
				.if eax
					dec		esi
					jmp		@b
				.endif
				.if esi!=edi
					invoke GetCpFromLine,ebx,esi
					mov		chrg.cpMin,eax
					mov		chrg.cpMax,eax
					invoke SendMessage,hWin,EM_EXSETSEL,0,addr chrg
				.endif
				pop		esi
				pop		edi
				.if [ebx].EDIT.fsplitt
					invoke InvalidateEdit,ebx,[ebx].EDIT.edta.hwnd
					invoke InvalidateEdit,ebx,[ebx].EDIT.edtb.hwnd
				.endif
				invoke SendMessage,hWin,REM_VCENTER,0,0
			.endif
			ret
		align 4
		_REM_EXPAND:
			;wParam=Line
			;lParam=0
			invoke Expand,ebx,wParam
			push	eax
			invoke InvalidateEdit,ebx,[ebx].EDIT.edta.hwnd
			invoke InvalidateEdit,ebx,[ebx].EDIT.edtb.hwnd
			pop		eax
			ret
		align 4
		_REM_EXPANDALL:
			;wParam=0
			;lParam=0
			invoke ExpandAll,ebx
			.if eax
				.if [ebx].EDIT.fsplitt
					invoke InvalidateEdit,ebx,[ebx].EDIT.edta.hwnd
					invoke InvalidateEdit,ebx,[ebx].EDIT.edtb.hwnd
				.endif
				invoke SendMessage,hWin,REM_VCENTER,0,0
			.endif
			ret
		align 4
		_REM_LOCKLINE:
			;wParam=Line
			;lParam=TRUE/FALSE
			invoke LockLine,ebx,wParam,lParam
			ret
		align 4
		_REM_ISLINELOCKED:
			;wParam=Line
			;lParam=0
			invoke IsLineLocked,ebx,wParam
			.if eax
				mov		eax,TRUE
			.endif
			ret
		align 4
		_REM_HIDELINE:
			;wParam=Line
			;lParam=TRUE/FALSE
			invoke HideLine,ebx,wParam,lParam
			push	eax
			invoke InvalidateEdit,ebx,[ebx].EDIT.edta.hwnd
			invoke InvalidateEdit,ebx,[ebx].EDIT.edtb.hwnd
			pop		eax
			ret
		align 4
		_REM_ISLINEHIDDEN:
			;wParam=Line
			;lParam=0
			invoke IsLineHidden,ebx,wParam
			.if eax
				mov		eax,TRUE
			.endif
			ret
		align 4
		_REM_AUTOINDENT:
			;wParam=0
			;lParam=TRUE/FALSE
			mov		eax,lParam
			mov		[ebx].EDIT.fIndent,eax
			ret
		align 4
		_REM_TABWIDTH:
			;wParam=nChars
			;lParam=0
			mov		eax,wParam
			mov		[ebx].EDIT.nTab,eax
			mov		eax,lParam
			mov		[ebx].EDIT.fExpandTab,eax
			invoke SetFont,ebx,addr [ebx].EDIT.fnt
			invoke InvalidateEdit,ebx,[ebx].EDIT.edta.hwnd
			invoke InvalidateEdit,ebx,[ebx].EDIT.edtb.hwnd
			xor		eax,eax
			ret
		align 4
		_REM_SELBARWIDTH:
			;wParam=nWidth
			;lParam=0
			mov		eax,wParam
			mov		[ebx].EDIT.selbarwt,eax
			invoke InvalidateEdit,ebx,[ebx].EDIT.edta.hwnd
			invoke InvalidateEdit,ebx,[ebx].EDIT.edtb.hwnd
			xor		eax,eax
			ret
		align 4
		_REM_LINENUMBERWIDTH:
			;wParam=nWidth
			;lParam=0
			mov		eax,wParam
			mov		[ebx].EDIT.nlinenrwt,eax
			.if [ebx].EDIT.linenrwt
				mov		[ebx].EDIT.linenrwt,eax
				invoke InvalidateEdit,ebx,[ebx].EDIT.edta.hwnd
				invoke InvalidateEdit,ebx,[ebx].EDIT.edtb.hwnd
			.endif
			xor		eax,eax
			ret
		align 4
		_REM_MOUSEWHEEL:
			;wParam=nLines
			;lParam=0
			mov		eax,wParam
			mov		[ebx].EDIT.nScroll,eax
			ret
		align 4
		_REM_SUBCLASS:
			;wParam=0
			;lParam=lpWndProc
			invoke SetWindowLong,[ebx].EDIT.edta.hwnd,GWL_WNDPROC,lParam
			invoke SetWindowLong,[ebx].EDIT.edtb.hwnd,GWL_WNDPROC,lParam
			ret
		align 4
		_REM_SETSPLIT:
			;wParam=nSplit
			;lParam=0
			mov		eax,wParam
			and		eax,1FFh
			mov		[ebx].EDIT.fsplitt,eax
			.if !eax
				mov		eax,[ebx].EDIT.focus
				.if eax==[ebx].EDIT.edta.hwnd
					mov		eax,[ebx].EDIT.edta.cpxmax
					mov		[ebx].EDIT.edtb.cpxmax,eax
					mov		eax,[ebx].EDIT.edta.cpy
					mov		[ebx].EDIT.edtb.cpy,eax
				.endif
			.endif
			call	NestedProc_SizeIt
			invoke SetFocus,[ebx].EDIT.edtb.hwnd
			invoke SetCaretVisible,[ebx].EDIT.edtb.hwnd,[ebx].EDIT.edtb.cpy
			ret
		align 4
		_REM_GETSPLIT:
			;wParam=0
			;lParam=0
			mov		eax,[ebx].EDIT.fsplitt
			ret
		align 4
		_REM_VCENTER:
			;wParam=0
			;lParam=0
			mov		eax,[esi].RAEDT.rc.bottom
			shr		eax,1
			mov		ecx,[ebx].EDIT.fntinfo.fntht
			xor		edx,edx
			div		ecx
			mul		ecx
			push	eax
			invoke GetLineFromCp,ebx,[ebx].EDIT.cpMin
			invoke GetYpFromLine,ebx,eax
			pop		edx
			.if eax>edx
				sub		eax,edx
			.else
				xor		eax,eax
			.endif
			mov		[esi].RAEDT.cpy,eax
			invoke SetCaretVisible,[esi].RAEDT.hwnd,[esi].RAEDT.cpy
			invoke InvalidateEdit,ebx,[esi].RAEDT.hwnd
			xor		eax,eax
			ret
		align 4
		_REM_REPAINT:
			;wParam=0
			;lParam=TRUE/FALSE (Paint Now)
			invoke InvalidateRect,[ebx].EDIT.edta.hwnd,NULL,FALSE
			invoke InvalidateRect,[ebx].EDIT.edta.hvscroll,NULL,TRUE
			invoke InvalidateRect,[ebx].EDIT.edtb.hwnd,NULL,FALSE
			invoke InvalidateRect,[ebx].EDIT.edtb.hvscroll,NULL,TRUE
			invoke InvalidateRect,[ebx].EDIT.hhscroll,NULL,TRUE
			invoke InvalidateRect,[ebx].EDIT.hgrip,NULL,TRUE
			invoke InvalidateRect,[ebx].EDIT.hnogrip,NULL,TRUE
			invoke InvalidateRect,[ebx].EDIT.hsbtn,NULL,TRUE
			invoke InvalidateRect,[ebx].EDIT.hlin,NULL,TRUE
			invoke InvalidateRect,[ebx].EDIT.hexp,NULL,TRUE
			invoke InvalidateRect,[ebx].EDIT.hcol,NULL,TRUE
			invoke InvalidateRect,[ebx].EDIT.hlock,NULL,TRUE
			invoke InvalidateRect,[ebx].EDIT.hsta,NULL,TRUE
			.if lParam
				invoke UpdateWindow,[ebx].EDIT.edta.hwnd
				invoke UpdateWindow,[ebx].EDIT.edtb.hwnd
			.endif
			xor		eax,eax
			ret
		align 4
		_REM_BMCALLBACK:
			;wParam=0
			;lParam=lpBmProc
			mov		eax,lParam
			mov		[ebx].EDIT.lpBmCB,eax
			ret
		align 4
		_REM_READONLY:
			;wParam=0
			;lParam=TRUE/FALSE
			invoke GetWindowLong,hWin,GWL_STYLE
			.if lParam
				or		eax,STYLE_READONLY
			.else
				and		eax,-1 xor STYLE_READONLY
			.endif
			mov		[ebx].EDIT.fstyle,eax
			invoke SetWindowLong,hWin,GWL_STYLE,eax
			invoke InvalidateRect,[ebx].EDIT.hsta,NULL,TRUE
			xor		eax,eax
			ret
		align 4
		_REM_INVALIDATELINE:
			;wParam=nLine
			;lParam=0
			invoke InvalidateLine,ebx,[ebx].EDIT.edta.hwnd,wParam
			invoke InvalidateLine,ebx,[ebx].EDIT.edtb.hwnd,wParam
			xor		eax,eax
			ret
		align 4
		_REM_SETPAGESIZE:
			;wParam=nLines
			;lParam=0
			mov		eax,wParam
			mov		[ebx].EDIT.nPageBreak,eax
			invoke InvalidateEdit,ebx,[ebx].EDIT.edta.hwnd
			invoke InvalidateEdit,ebx,[ebx].EDIT.edtb.hwnd
			xor		eax,eax
			ret
		align 4
		_REM_GETPAGESIZE:
			;wParam=0
			;lParam=0
			mov		eax,[ebx].EDIT.nPageBreak
			ret
		align 4
		_REM_GETCHARTAB:
			;wParam=nChar
			;lParam=0
			mov		edx,wParam
			and		edx,0FFh
			movzx	eax,byte ptr [edx+offset CharTab]
			ret
		align 4
		_REM_SETCHARTAB:
			;wParam=nChar
			;lParam=nType
			mov		edx,wParam
			and		edx,0FFh
			mov		eax,lParam
			mov		byte ptr [edx+offset CharTab],al
			ret
		align 4
		_REM_SETCOMMENTBLOCKS:
			;wParam=lpStart
			;lParam=lpEnd
			invoke SetCommentBlocks,ebx,wParam,lParam
			ret
		align 4
		_REM_SETWORDGROUP:
			;wParam=0
			;lParam=nGroup (0-15)
			mov		eax,lParam
			and		eax,0Fh
			mov		[ebx].EDIT.nWordGroup,eax
			ret
		align 4
		_REM_GETWORDGROUP:
			;wParam=0
			;lParam=0
			mov		eax,[ebx].EDIT.nWordGroup
			ret
		align 4
		_REM_SETBMID:
			;wParam=nLine
			;lParam=nBmID
			mov		edx,wParam
			shl		edx,2
			.if edx<[ebx].EDIT.rpLineFree
				add		edx,[ebx].EDIT.hLine
				mov		edx,[edx].LINE.rpChars
				add		edx,[ebx].EDIT.hChars
				mov		eax,lParam
				mov		[edx].CHARS.bmid,eax
			.endif
			ret
		align 4
		_REM_GETBMID:
			;wParam=nLine
			;lParam=0
			xor		eax,eax
			mov		edx,wParam
			shl		edx,2
			.if edx<[ebx].EDIT.rpLineFree
				add		edx,[ebx].EDIT.hLine
				mov		edx,[edx].LINE.rpChars
				add		edx,[ebx].EDIT.hChars
				mov		eax,[edx].CHARS.bmid
			.endif
			ret
		align 4
		_REM_ISCHARPOS:
			;wParam=CP
			;lParam=0
			invoke IsCharPos,ebx,wParam
			ret
		align 4
		_REM_HIDELINES:
			;wParam=nLine
			;lParam=nLines
			xor		eax,eax
			.if lParam>1
				invoke GetBookMark,ebx,wParam
				.if !eax
					push	[ebx].EDIT.nHidden
					mov		ecx,lParam
					mov		edx,wParam
					dec		ecx
					.while ecx
						inc		edx
						push	ecx
						push	edx
						invoke HideLine,ebx,edx,TRUE
						.if eax
							pop		edx
							push	edx
							shl		edx,2
							.if edx<[ebx].EDIT.rpLineFree
								add		edx,[ebx].EDIT.hLine
								mov		edx,[edx].LINE.rpChars
								add		edx,[ebx].EDIT.hChars
								mov		eax,nBmid
								inc		eax
								mov		[edx].CHARS.bmid,eax
							.endif
						.endif
						pop		edx
						pop		ecx
						dec		ecx
					.endw
					pop		edx
					mov		eax,[ebx].EDIT.nHidden
					sub		eax,edx
					.if eax
						push	eax
						invoke SetBookMark,ebx,wParam,8
						mov		eax,[ebx].EDIT.cpMin
						.if eax>[ebx].EDIT.cpMax
							mov		eax,[ebx].EDIT.cpMax
						.endif
						mov		[ebx].EDIT.cpMin,eax
						mov		[ebx].EDIT.cpMax,eax
						mov		eax,[ebx].EDIT.rpLineFree
						shr		eax,2
						sub		eax,[ebx].EDIT.nHidden
						mov		ecx,[ebx].EDIT.fntinfo.fntht
						mul		ecx
						xor		ecx,ecx
						.if eax<[ebx].EDIT.edta.cpy
							mov		[ebx].EDIT.edta.cpy,eax
							mov		[ebx].EDIT.edta.topyp,ecx
							mov		[ebx].EDIT.edta.topln,ecx
							mov		[ebx].EDIT.edta.topcp,ecx
						.endif
						.if eax<[ebx].EDIT.edtb.cpy
							mov		[ebx].EDIT.edtb.cpy,eax
							mov		[ebx].EDIT.edtb.topyp,ecx
							mov		[ebx].EDIT.edtb.topln,ecx
							mov		[ebx].EDIT.edtb.topcp,ecx
						.endif
						invoke InvalidateEdit,ebx,[ebx].EDIT.edta.hwnd
						invoke InvalidateEdit,ebx,[ebx].EDIT.edtb.hwnd
						pop		eax
					.endif
				.else
					xor		eax,eax
				.endif
			.endif
			ret
		align 4
		_REM_SETDIVIDERLINE:
			;wParam=nLine
			;lParam=TRUE/FALSE
			mov		edx,wParam
			shl		edx,2
			.if edx<[ebx].EDIT.rpLineFree
				add		edx,[ebx].EDIT.hLine
				mov		edx,[edx].LINE.rpChars
				add		edx,[ebx].EDIT.hChars
				.if lParam
					or		[edx].CHARS.state,STATE_DIVIDERLINE
				.else
					and		[edx].CHARS.state,-1 xor STATE_DIVIDERLINE
				.endif
				invoke InvalidateLine,ebx,[ebx].EDIT.edta.hwnd,wParam
				invoke InvalidateLine,ebx,[ebx].EDIT.edtb.hwnd,wParam
			.endif
			xor		eax,eax
			ret
		align 4
		_REM_ISINBLOCK:
			;wParam=nLine
			;lParam=lpRABLOCKDEF
			invoke IsInBlock,ebx,wParam,lParam
			ret
		align 4
		_REM_TRIMSPACE:
			;wParam=nLine
			;lParam=fLeft
			invoke TrimSpace,ebx,wParam,lParam
			.if eax
				push	eax
				invoke SelChange,ebx,SEL_TEXT
				pop		eax
			.endif
			ret
		align 4
		_REM_SAVESEL:
			;wParam=0
			;lParam=0
			mov		eax,[ebx].EDIT.cpMin
			mov		[ebx].EDIT.savesel.cpMin,eax
			mov		eax,[ebx].EDIT.cpMax
			mov		[ebx].EDIT.savesel.cpMax,eax
			xor		eax,eax
			ret
		align 4
		_REM_RESTORESEL:
			;wParam=0
			;lParam=0
			.if ![ebx].EDIT.fHideSel
				mov		eax,[ebx].EDIT.cpMin
				.if eax!=[ebx].EDIT.cpMax
					invoke InvalidateSelection,ebx,[ebx].EDIT.edta.hwnd,[ebx].EDIT.cpMin,[ebx].EDIT.cpMax
					invoke InvalidateSelection,ebx,[ebx].EDIT.edtb.hwnd,[ebx].EDIT.cpMin,[ebx].EDIT.cpMax
				.endif
			.endif
			invoke GetCharPtr,ebx,[ebx].EDIT.savesel.cpMax
			mov		[ebx].EDIT.cpMax,ecx
			invoke GetCharPtr,ebx,[ebx].EDIT.savesel.cpMin
			mov		[ebx].EDIT.cpMin,ecx
			.if ![ebx].EDIT.fHideSel
				invoke TestExpand,ebx,[ebx].EDIT.line
				mov		eax,[ebx].EDIT.cpMin
				.if eax!=[ebx].EDIT.cpMax
					invoke InvalidateSelection,ebx,[ebx].EDIT.edta.hwnd,[ebx].EDIT.cpMin,[ebx].EDIT.cpMax
					invoke InvalidateSelection,ebx,[ebx].EDIT.edtb.hwnd,[ebx].EDIT.cpMin,[ebx].EDIT.cpMax
					invoke SetCaret,ebx,[esi].RAEDT.cpy
					invoke SetCpxMax,ebx,[esi].RAEDT.hwnd
				.endif
			.endif
			invoke SelChange,ebx,SEL_TEXT
			xor		eax,eax
			ret
		align 4
		_REM_GETCURSORWORD:
			;wParam=BuffSize
			;lParam=lpBuff
			mov		edi,lParam
			mov		byte ptr [edi],0
			invoke GetCursorPos,addr pt
			invoke ScreenToClient,hWin,addr pt
			mov		eax,[ebx].EDIT.selbarwt
			add		eax,[ebx].EDIT.linenrwt
			.if eax<=pt.x
				invoke ChildWindowFromPoint,hWin,pt.x,pt.y
				.if eax==[ebx].EDIT.edta.hwnd
					lea		esi,[ebx].EDIT.edta
				.else
					lea		esi,[ebx].EDIT.edtb
				.endif
				invoke ClientToScreen,hWin,addr pt
				invoke ScreenToClient,[esi].RAEDT.hwnd,addr pt
				invoke GetCharFromPos,ebx,[esi].RAEDT.cpy,pt.x,pt.y
				push	eax
				mov		edx,eax
				push	pt.x
				invoke GetPosFromChar,ebx,edx,addr pt
				pop		edx
				pop		eax
				sub		edx,[ebx].EDIT.fntinfo.fntwt
				.if edx<=pt.x
					invoke GetWordStart,ebx,eax,[ebx].EDIT.nCursorWordType
					mov		esi,[ebx].EDIT.rpChars
					mov		ecx,eax
					sub		ecx,[ebx].EDIT.cpLine
					push	ecx
					push	eax
					invoke GetWordEnd,ebx,eax,[ebx].EDIT.nCursorWordType
					pop		ecx
					pop		edx
					sub		eax,ecx
					mov		ecx,eax
					.if ecx>=wParam
						mov		ecx,wParam
						dec		ecx
					.endif
					add		esi,[ebx].EDIT.hChars
					add		esi,edx
					add		esi,sizeof CHARS
					mov		eax,ecx
					rep movsb
					mov		byte ptr [edi],0
					mov		eax,[ebx].EDIT.line
				.else
					mov		eax,-1
				.endif
			.else
				mov		eax,-1
			.endif
			ret
		align 4
		_REM_SETSEGMENTBLOCK:
			;wParam=nLine
			;lParam=TRUE/FALSE
			mov		edx,wParam
			shl		edx,2
			.if edx<[ebx].EDIT.rpLineFree
				add		edx,[ebx].EDIT.hLine
				mov		edx,[edx].LINE.rpChars
				add		edx,[ebx].EDIT.hChars
				.if lParam
					or		[edx].CHARS.state,STATE_SEGMENTBLOCK
				.else
					and		[edx].CHARS.state,-1 xor STATE_SEGMENTBLOCK
				.endif
			.endif
			xor		eax,eax
			ret
		align 4
		_REM_GETMODE:
			;wParam=0
			;lParam=0
			mov		eax,[ebx].EDIT.nMode
;			.if [ebx].EDIT.fOvr
;				or		eax,MODE_OVERWRITE
;			.endif
			ret
		align 4
		_REM_SETMODE:
			;wParam=nMode
			;lParam=0
			mov		eax,wParam
			.if !(eax&MODE_OVERWRITE)
				mov		[ebx].EDIT.fOvr,FALSE
			.else
				mov		[ebx].EDIT.fOvr,TRUE
			.endif
			.if ![ebx].EDIT.fntinfo.monospace
				and		eax,-1 xor MODE_BLOCK
			.endif
			mov		edx,[ebx].EDIT.nMode
			mov		[ebx].EDIT.nMode,eax
			xor		eax,edx
			.if eax&MODE_BLOCK
				.if ![ebx].EDIT.fntinfo.monospace
					and		[ebx].EDIT.nMode,-1 xor MODE_BLOCK
				.endif
				.if !([ebx].EDIT.nMode&MODE_BLOCK)
					mov		eax,2
				.else
					mov		eax,3
				.endif
				mov		edx,[ebx].EDIT.fntinfo.fntht
				invoke CreateCaret,[ebx].EDIT.focus,NULL,eax,edx
				invoke GetCaretPos,addr pt
				invoke GetCharFromPos,ebx,[esi].RAEDT.cpy,pt.x,pt.y
				mov		[ebx].EDIT.cpMin,eax
				mov		[ebx].EDIT.cpMax,eax
				.if !([ebx].EDIT.nMode&MODE_BLOCK)
					xor		eax,eax
					mov		[ebx].EDIT.blrg.lnMin,eax
					mov		[ebx].EDIT.blrg.clMin,eax
					mov		[ebx].EDIT.blrg.lnMax,eax
					mov		[ebx].EDIT.blrg.clMax,eax
				.else
					invoke SetBlockFromCp,ebx,[ebx].EDIT.cpMin,FALSE
				.endif
				invoke SetCaretVisible,hWin,[esi].RAEDT.cpy
				invoke SetCaret,ebx,[esi].RAEDT.cpy
				invoke InvalidateRect,[ebx].EDIT.edta.hwnd,NULL,TRUE
				invoke InvalidateRect,[ebx].EDIT.edtb.hwnd,NULL,TRUE
				invoke SelChange,ebx,SEL_TEXT
			.endif
			xor		eax,eax
			ret
		align 4
		_REM_GETBLOCK:
			;wParam=0
			;lParam=lpBLOCKRANGE
			mov		edx,lParam
			mov		eax,[ebx].EDIT.blrg.lnMin
			mov		[edx].BLOCKRANGE.lnMin,eax
			mov		eax,[ebx].EDIT.blrg.clMin
			mov		[edx].BLOCKRANGE.clMin,eax
			mov		eax,[ebx].EDIT.blrg.lnMax
			mov		[edx].BLOCKRANGE.lnMax,eax
			mov		eax,[ebx].EDIT.blrg.clMax
			mov		[edx].BLOCKRANGE.clMax,eax
			xor		eax,eax
			ret
		align 4
		_REM_SETBLOCK:
			;wParam=0
			;lParam=lpBLOCKRANGE
			.if [ebx].EDIT.nMode&MODE_BLOCK
				invoke GetBlockRects,ebx,addr oldrects
				mov		edx,lParam
				mov		eax,[edx].BLOCKRANGE.lnMin
				mov		[ebx].EDIT.blrg.lnMin,eax
				mov		eax,[edx].BLOCKRANGE.clMin
				mov		[ebx].EDIT.blrg.clMin,eax
				mov		eax,[edx].BLOCKRANGE.lnMax
				mov		[ebx].EDIT.blrg.lnMax,eax
				mov		eax,[edx].BLOCKRANGE.clMax
				mov		[ebx].EDIT.blrg.clMax,eax
				invoke GetBlockCp,ebx,[ebx].EDIT.blrg.lnMin,[ebx].EDIT.blrg.clMin
				mov		[ebx].EDIT.cpMin,eax
				mov		[ebx].EDIT.cpMax,eax
				invoke InvalidateBlock,ebx,addr oldrects
				invoke SetCaretVisible,hWin,[esi].RAEDT.cpy
				invoke SetCaret,ebx,[esi].RAEDT.cpy
				invoke SelChange,ebx,SEL_TEXT
			.endif
			xor		eax,eax
			ret
		align 4
		_REM_BLOCKINSERT:
			.if [ebx].EDIT.nMode&MODE_BLOCK
				invoke IsSelectionLocked,ebx,[ebx].EDIT.cpMin,[ebx].EDIT.cpMax
				.if eax!=0
					jmp		ErrBeep
				.endif
				inc		nUndoid
				mov		eax,[ebx].EDIT.blrg.lnMin
				mov		edx,[ebx].EDIT.blrg.lnMax
				.if eax<edx
					xchg	eax,edx
				.endif
				sub		eax,edx
				inc		eax
				mov		edi,eax
				invoke strlen,lParam
				mov		esi,eax
				add		eax,2
				mul		edi
				inc		eax
				invoke xGlobalAlloc,GMEM_FIXED or GMEM_ZEROINIT,eax
				push	eax
				mov		edx,eax
				.while edi
					push	esi
					mov		ecx,lParam
					.while esi
						mov		al,[ecx]
						mov		[edx],al
						inc		ecx
						inc		edx
						dec		esi
					.endw
					mov		byte ptr [edx],0Dh
					inc		edx
					mov		byte ptr [edx],0Ah
					inc		edx
					pop		esi
					dec		edi
				.endw
				pop		eax
				push	eax
				invoke Paste,ebx,[ebx].EDIT.focus,eax
				pop		eax
				invoke GlobalFree,eax
				inc		nUndoid
				invoke InvalidateEdit,ebx,[ebx].EDIT.edta.hwnd
				invoke InvalidateEdit,ebx,[ebx].EDIT.edtb.hwnd
			.endif
			xor		eax,eax
			ret
		align 4
		_REM_LOCKUNDOID:
			.if wParam
				mov		eax,nUndoid
				inc		eax
				mov		[ebx].EDIT.lockundoid,eax
				inc		eax
				mov		nUndoid,eax
			.else
				mov		[ebx].EDIT.lockundoid,0
			.endif
			xor		eax,eax
			ret
		align 4
		_REM_ADDBLOCKDEF:
			invoke SetBlockDef,lParam
			xor		eax,eax
			ret
		align 4
		_REM_CONVERT:
			.if !([ebx].EDIT.nMode&MODE_BLOCK)
				invoke IsSelectionLocked,ebx,[ebx].EDIT.cpMin,[ebx].EDIT.cpMax
				.if eax!=0
					jmp		ErrBeep
				.endif
				.if wParam==CONVERT_TABTOSPACE || wParam==CONVERT_SPACETOTAB
					invoke ConvertIndent,ebx,wParam
				.else
					invoke ConvertCase,ebx,wParam
				.endif
				invoke InvalidateEdit,ebx,[ebx].EDIT.edta.hwnd
				invoke InvalidateEdit,ebx,[ebx].EDIT.edtb.hwnd
				invoke SetCaret,ebx,[esi].RAEDT.cpy
			.endif
			xor		eax,eax
			ret
		align 4
		_REM_BRACKETMATCH:
			.if lParam
				mov		edx,lParam
				mov		ecx,offset bracketstart
				.while byte ptr [edx] && byte ptr [edx]!=','
					mov		al,[edx]
					mov		[ecx],al
					inc		edx
					inc		ecx
				.endw
				mov		byte ptr [ecx],0
				mov		ecx,offset bracketend
				.if byte ptr [edx]==','
					inc		edx
					.while byte ptr [edx] && byte ptr [edx]!=','
						mov		al,[edx]
						mov		[ecx],al
						inc		edx
						inc		ecx
					.endw
				.endif
				mov		byte ptr [ecx],0
				mov		ecx,offset bracketcont
				.if byte ptr [edx]==','
					inc		edx
					.while byte ptr [edx]
						mov		al,[edx]
						mov		[ecx],al
						inc		edx
						inc		ecx
					.endw
				.endif
				mov		byte ptr [ecx],0FFh
				xor		eax,eax
			.else
				mov		eax,[ebx].EDIT.cpMin
				.if eax==[ebx].EDIT.cpMax
					invoke GetChar,ebx,[ebx].EDIT.cpMin
					invoke BracketMatch,ebx,eax,[ebx].EDIT.cpMin
				.endif
			.endif
			ret
		align 4
		_REM_COMMAND:
			invoke GetFocus
			.if eax==[ebx].EDIT.edta.hwnd || eax==[ebx].EDIT.edtb.hwnd
				mov		ecx,wParam
				mov		fAlt,0
				mov		fControl,0
				mov		fShift,0
				.if ecx&CMD_ALT
					mov		fAlt,TRUE
				.endif
				.if ecx&CMD_CTRL
					mov		fControl,TRUE
				.endif
				.if ecx&CMD_SHIFT
					mov		fShift,TRUE
				.endif
				movzx	ecx,cl
				invoke EditFunc,eax,ecx,fAlt,fShift,fControl
			.endif
			xor		eax,eax
			ret
		align 4
		_REM_CASEWORD:
			;wParam=cp
			;lParam=lpBuff
			mov		edx,wParam
			invoke GetWordStart,ebx,edx,0
			mov		esi,[ebx].EDIT.rpChars
			sub		eax,[ebx].EDIT.cpLine
			add		esi,[ebx].EDIT.hChars
			mov		ecx,[esi].CHARS.len
			add		esi,eax
			sub		ecx,eax
			add		esi,sizeof CHARS
			mov		edi,lParam
			.while byte ptr [edi] && sdword ptr ecx>=0
				mov		al,[edi]
				mov		[esi],al
				inc		edi
				inc		esi
				dec		ecx
			.endw
			xor		eax,eax
			ret
		align 4
		_REM_GETBLOCKEND:
			;wParam=nLine
			;lParam=0
			invoke CollapseGetEnd,ebx,wParam
			ret
		align 4
		_REM_SETLOCK:
			;wParam=TRUE/FALSE
			;lParam=0
			.if wParam
				mov		eax,TRUE
			.else
				xor		eax,eax
			.endif
			mov		[ebx].EDIT.fLock,eax
			invoke CheckDlgButton,hWin,-5,eax
			xor		eax,eax
			ret
		align 4
		_REM_GETLOCK:
			;wParam=0
			;lParam=0
			mov		eax,[ebx].EDIT.fLock
			ret
		align 4
		_REM_GETWORDFROMPOS:
			;wParam=cp
			;lParam=lpBuff
			invoke GetWordStart,ebx,wParam,0
			mov		esi,[ebx].EDIT.rpChars
			mov		ecx,eax
			sub		ecx,[ebx].EDIT.cpLine
			push	ecx
			push	eax
			invoke GetWordEnd,ebx,eax,0
			pop		ecx
			pop		edx
			sub		eax,ecx
			mov		ecx,eax
			mov		edi,lParam
			add		esi,[ebx].EDIT.hChars
			add		esi,edx
			add		esi,sizeof CHARS
			mov		eax,ecx
			rep movsb
			mov		byte ptr [edi],0
			ret
		align 4
		_REM_SETNOBLOCKLINE:
			;wParam=Line
			;lParam=TRUE/FALSE
			invoke NoBlockLine,ebx,wParam,lParam
			ret
		align 4
		_REM_ISLINENOBLOCK:
			;wParam=Line
			;lParam=0
			invoke IsLineNoBlock,ebx,wParam
			.if eax
				mov		eax,TRUE
			.endif
			ret
		align 4
		_REM_SETALTHILITELINE:
			;wParam=nLine
			;lParam=TRUE/FALSE
			invoke AltHiliteLine,ebx,wParam,lParam
			ret
		align 4
		_REM_ISLINEALTHILITE:
			;wParam=nLine
			;lParam=0
			invoke IsLineAltHilite,ebx,wParam
			.if eax
				mov		eax,TRUE
			.endif
			ret
		align 4
		_REM_SETCURSORWORDTYPE:
			;wParam=Type
			;lParam=0
			mov		eax,wParam
			mov		[ebx].EDIT.nCursorWordType,eax
			ret
		align 4
		_REM_SETBREAKPOINT:
			;wParam=nLine
			;lParam=TRUE/FALSE
			invoke SetBreakpoint,ebx,wParam,lParam
			invoke InvalidateLine,ebx,[ebx].EDIT.edta.hwnd,wParam
			invoke InvalidateLine,ebx,[ebx].EDIT.edtb.hwnd,wParam
			ret
		align 4
		_REM_NEXTBREAKPOINT:
			;wParam=nLine
			;lParam=0
			invoke NextBreakpoint,ebx,wParam
			ret
		align 4
		_REM_GETLINESTATE:
			;wParam=nLine
			;lParam=0
			invoke GetLineState,ebx,wParam
			ret
		align 4
		_REM_SETERROR:
			;wParam=nLine
			;lParam=nErrID
			invoke SetError,ebx,wParam,lParam
			invoke InvalidateLine,ebx,[ebx].EDIT.edta.hwnd,wParam
			invoke InvalidateLine,ebx,[ebx].EDIT.edtb.hwnd,wParam
			ret
		_REM_GETERROR:
			;wParam=nLine
			;lParam=0
			invoke GetError,ebx,wParam
			ret
		align 4
		_REM_NEXTERROR:
			;wParam=nLine
			;lParam=0
			invoke NextError,ebx,wParam
			ret
		align 4
		_REM_CHARTABINIT:
			;wParam=0
			;lParam=0
			mov		esi,offset CharTabInit
			mov		edi,offset CharTab
			mov		ecx,256
			rep		movsb
			ret
		align 4
		_REM_LINEREDTEXT:
			;wParam=nLine
			;lParam=TRUE/FALSE
			invoke SetRedText,ebx,wParam,lParam
			invoke InvalidateLine,ebx,[ebx].EDIT.edta.hwnd,wParam
			invoke InvalidateLine,ebx,[ebx].EDIT.edtb.hwnd,wParam
			ret
		align 4
		_REM_SETSTYLEEX:
			mov		eax,wParam
			mov		[ebx].EDIT.fstyleex,eax
			invoke InvalidateRect,hWin,NULL,TRUE
			ret
		align 4
		_REM_GETUNICODE:
			mov		eax,[ebx].EDIT.funicode
			ret
		align 4
		_REM_SETUNICODE:
			mov		eax,wParam
			mov		[ebx].EDIT.funicode,eax
			ret
		align 4
		_REM_SETCHANGEDSTATE:
			invoke SetChangedState,ebx,wParam
			ret
		align 4
		_REM_SETTOOLTIP:
			mov		eax,wParam
			.if eax==1
				mov		eax,[ebx].EDIT.hsta
			.elseif eax==2
				mov		eax,[ebx].EDIT.hsbtn
			.elseif eax==3
				mov		eax,[ebx].EDIT.hlin
			.elseif eax==4
				mov		eax,[ebx].EDIT.hexp
			.elseif eax==5
				mov		eax,[ebx].EDIT.hcol
			.elseif eax==6
				mov		eax,[ebx].EDIT.hlock
			.else
				xor		eax,eax
			.endif
			.if eax
				mov		edx,lParam
				call NestedProc_SetToolTip
			.endif
			ret
		align 4
		_REM_HILITEACTIVELINE:
			mov		eax,lParam
			mov		[ebx].EDIT.fhilite,eax
			invoke HiliteLine,ebx,[ebx].EDIT.line,[ebx].EDIT.fhilite
			ret
		align 4
		_REM_GETUNDO:
			invoke GetUndo,ebx,wParam,lParam
			ret
		align 4
		_REM_SETUNDO:
			invoke SetUndo,ebx,wParam,lParam
			ret
		align 4
		_REM_GETLINEBEGIN:
			invoke GetLineBegin,ebx,wParam
			ret

.data

align 4
_REM_BASE \
	dd _REM_SETHILITEWORDS		;equ REM_BASE+0
	dd _REM_SETFONT				;equ REM_BASE+1
	dd _REM_GETFONT				;equ REM_BASE+2	
	dd _REM_SETCOLOR			;equ REM_BASE+3	
	dd _REM_GETCOLOR			;equ REM_BASE+4	
	dd _REM_SETHILITELINE		;equ REM_BASE+5	
	dd _REM_GETHILITELINE		;equ REM_BASE+6	
	dd _REM_SETBOOKMARK			;equ REM_BASE+7	
	dd _REM_GETBOOKMARK			;equ REM_BASE+8	
	dd _REM_CLRBOOKMARKS		;equ REM_BASE+9	
	dd _REM_NXTBOOKMARK			;equ REM_BASE+10
	dd _REM_PRVBOOKMARK			;equ REM_BASE+11
	dd _REM_FINDBOOKMARK		;equ REM_BASE+12
	dd _REM_SETBLOCKS			;equ REM_BASE+13
	dd _REM_ISLINE				;equ REM_BASE+14
	dd _REM_GETWORD				;equ REM_BASE+15
	dd _REM_COLLAPSE			;equ REM_BASE+16
	dd _REM_COLLAPSEALL			;equ REM_BASE+17
	dd _REM_EXPAND				;equ REM_BASE+18
	dd _REM_EXPANDALL			;equ REM_BASE+19
	dd _REM_LOCKLINE			;equ REM_BASE+20
	dd _REM_ISLINELOCKED		;equ REM_BASE+21
	dd _REM_HIDELINE			;equ REM_BASE+22
	dd _REM_ISLINEHIDDEN		;equ REM_BASE+23
	dd _REM_AUTOINDENT			;equ REM_BASE+24
	dd _REM_TABWIDTH			;equ REM_BASE+25
	dd _REM_SELBARWIDTH			;equ REM_BASE+26
	dd _REM_LINENUMBERWIDTH		;equ REM_BASE+27
	dd _REM_MOUSEWHEEL			;equ REM_BASE+28
	dd _REM_SUBCLASS			;equ REM_BASE+29
	dd _REM_SETSPLIT			;equ REM_BASE+30
	dd _REM_GETSPLIT			;equ REM_BASE+31
	dd _REM_VCENTER				;equ REM_BASE+32
	dd _REM_REPAINT				;equ REM_BASE+33
	dd _REM_BMCALLBACK			;equ REM_BASE+34
	dd _REM_READONLY			;equ REM_BASE+35
	dd _REM_INVALIDATELINE		;equ REM_BASE+36
	dd _REM_SETPAGESIZE			;equ REM_BASE+37
	dd _REM_GETPAGESIZE			;equ REM_BASE+38
	dd _REM_GETCHARTAB			;equ REM_BASE+39
	dd _REM_SETCHARTAB			;equ REM_BASE+40
	dd _REM_SETCOMMENTBLOCKS	;equ REM_BASE+41
	dd _REM_SETWORDGROUP		;equ REM_BASE+42
	dd _REM_GETWORDGROUP		;equ REM_BASE+43
	dd _REM_SETBMID				;equ REM_BASE+44
	dd _REM_GETBMID				;equ REM_BASE+45
	dd _REM_ISCHARPOS			;equ REM_BASE+46
	dd _REM_HIDELINES			;equ REM_BASE+47
	dd _REM_SETDIVIDERLINE		;equ REM_BASE+48
	dd _REM_ISINBLOCK			;equ REM_BASE+49
	dd _REM_TRIMSPACE			;equ REM_BASE+50
	dd _REM_SAVESEL				;equ REM_BASE+51
	dd _REM_RESTORESEL			;equ REM_BASE+52
	dd _REM_GETCURSORWORD		;equ REM_BASE+53
	dd _REM_SETSEGMENTBLOCK		;equ REM_BASE+54
	dd _REM_GETMODE				;equ REM_BASE+55
	dd _REM_SETMODE				;equ REM_BASE+56
	dd _REM_GETBLOCK			;equ REM_BASE+57
	dd _REM_SETBLOCK			;equ REM_BASE+58
	dd _REM_BLOCKINSERT			;equ REM_BASE+59
	dd _REM_LOCKUNDOID			;equ REM_BASE+60
	dd _REM_ADDBLOCKDEF			;equ REM_BASE+61
	dd _REM_CONVERT				;equ REM_BASE+62
	dd _REM_BRACKETMATCH		;equ REM_BASE+63
	dd _REM_COMMAND				;equ REM_BASE+64
	dd _REM_CASEWORD			;equ REM_BASE+65
	dd _REM_GETBLOCKEND			;equ REM_BASE+66
	dd _REM_SETLOCK				;equ REM_BASE+67
	dd _REM_GETLOCK				;equ REM_BASE+68
	dd _REM_GETWORDFROMPOS		;equ REM_BASE+69
	dd _REM_SETNOBLOCKLINE		;equ REM_BASE+70
	dd _REM_ISLINENOBLOCK		;equ REM_BASE+71
	dd _REM_SETALTHILITELINE	;equ REM_BASE+72
	dd _REM_ISLINEALTHILITE		;equ REM_BASE+73
	dd _REM_SETCURSORWORDTYPE	;equ REM_BASE+74
	dd _REM_SETBREAKPOINT		;equ REM_BASE+75
	dd _REM_NEXTBREAKPOINT		;equ REM_BASE+76
	dd _REM_GETLINESTATE		;equ REM_BASE+77
	dd _REM_SETERROR			;equ REM_BASE+78
	dd _REM_GETERROR			;equ REM_BASE+79
	dd _REM_NEXTERROR			;equ REM_BASE+80
	dd _REM_CHARTABINIT			;equ REM_BASE+81
	dd _REM_LINEREDTEXT			;equ REM_BASE+82
	dd _REM_SETSTYLEEX			;equ REM_BASE+83
	dd _REM_GETUNICODE			;equ REM_BASE+84
	dd _REM_SETUNICODE			;equ REM_BASE+85
	dd _REM_SETCHANGEDSTATE		;equ REM_BASE+86
	dd _REM_SETTOOLTIP			;equ REM_BASE+87
	dd _REM_HILITEACTIVELINE	;equ REM_BASE+88
	dd _REM_GETUNDO				;equ REM_BASE+89
	dd _REM_SETUNDO				;equ REM_BASE+90
	dd _REM_GETLINEBEGIN		;equ REM_BASE+91

.code
align 4
		;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
		; END OF: RAEdit_REM_Msg_JumpTable.asm
	.endif
	.if eax>=EM_CANPASTE && eax<=EM_SETZOOM
		sub		eax,EM_CANPASTE
		.if eax>35
			invoke DefWindowProc,hWin,uMsg,wParam,lParam
			ret
		.endif
		jmp		DWORD PTR [offset _RICHEDIT_MSG+eax*4]
		; RAEdit_Richedit_Msg_JumpTable.asm
		;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
		align 4 
		_EM_EXLINEFROMCHAR:
			;wParam=0
			;lParam=cp
			invoke GetCharPtr,ebx,lParam
			mov		eax,edx
			ret
		align 4 
		_EM_EXSETSEL:
			;wParam=0
			;lParam=lpCHARRANGE
			.if !([ebx].EDIT.nMode&MODE_BLOCK)
				.if ![ebx].EDIT.fHideSel
					mov		eax,[ebx].EDIT.cpMin
					.if eax!=[ebx].EDIT.cpMax
						invoke InvalidateSelection,ebx,[ebx].EDIT.edta.hwnd,[ebx].EDIT.cpMin,[ebx].EDIT.cpMax
						invoke InvalidateSelection,ebx,[ebx].EDIT.edtb.hwnd,[ebx].EDIT.cpMin,[ebx].EDIT.cpMax
					.endif
				.endif
				mov		edi,lParam
				invoke GetCharPtr,ebx,[edi].CHARRANGE.cpMax
				mov		[ebx].EDIT.cpMax,ecx
				invoke GetCharPtr,ebx,[edi].CHARRANGE.cpMin
				mov		[ebx].EDIT.cpMin,ecx
				push	edx
				.if ![ebx].EDIT.fHideSel
					invoke TestExpand,ebx,[ebx].EDIT.line
					mov		eax,[ebx].EDIT.cpMin
					.if eax!=[ebx].EDIT.cpMax
						invoke InvalidateSelection,ebx,[ebx].EDIT.edta.hwnd,[ebx].EDIT.cpMin,[ebx].EDIT.cpMax
						invoke InvalidateSelection,ebx,[ebx].EDIT.edtb.hwnd,[ebx].EDIT.cpMin,[ebx].EDIT.cpMax
						invoke SetCaret,ebx,[esi].RAEDT.cpy
						invoke SetCpxMax,ebx,[esi].RAEDT.hwnd
					.endif
				.endif
				invoke SelChange,ebx,SEL_TEXT
				pop		eax
			.else
				xor		eax,eax
				dec		eax
			.endif
			ret
		align 4 
		_EM_EXGETSEL:
			;wParam=0
			;lParam=lpCHARRANGE
			mov		edx,lParam
			mov		eax,[ebx].EDIT.cpMin
			mov		ecx,[ebx].EDIT.cpMax
			.if eax>ecx
				xchg	eax,ecx
			.endif
			mov		[edx].CHARRANGE.cpMin,eax
			mov		[edx].CHARRANGE.cpMax,ecx
			xor		eax,eax
			ret
		align 4 
		_EM_FINDTEXTEX:
			;wParam=Flags
			;lParam=lpFINDTEXTEX
			.if !([ebx].EDIT.nMode&MODE_BLOCK)
				invoke FindTextEx,ebx,wParam,lParam
			.else
				xor		eax,eax
				dec		eax
			.endif
			ret
		align 4 
		_EM_GETTEXTRANGE:
			;wParam=0
			;lParam=lpTEXTRANGE
			mov		edx,lParam
			invoke GetText,ebx,[edx].TEXTRANGE.chrg.cpMin,[edx].TEXTRANGE.chrg.cpMax,[edx].TEXTRANGE.lpstrText,FALSE
			ret
		align 4 
		_EM_FINDWORDBREAK:
			;wParam=uFlags
			;lParam=cp
			mov		eax,wParam
			.if eax==WB_MOVEWORDLEFT
				invoke GetWordStart,ebx,lParam,0
			.elseif eax==WB_MOVEWORDRIGHT
				invoke GetWordEnd,ebx,lParam,0
			.else
				mov		eax,lParam
			.endif
			ret
		align 4 
		_EM_CANREDO:
			;wParam=0
			;lParam=0
			xor		eax,eax
			.if !([ebx].EDIT.nMode&MODE_BLOCK)
				mov		edx,[ebx].EDIT.hUndo
				add		edx,[ebx].EDIT.rpUndo
				mov		eax,[edx].RAUNDO.cb
				.if eax
					mov		eax,TRUE
				.endif
			.endif
			ret
		align 4 
		_EM_REDO:
			;wParam=0
			;lParam=0
			inc		nUndoid
			invoke Redo,ebx,[esi].RAEDT.hwnd
			inc		nUndoid
			ret
		align 4 
		_EM_HIDESELECTION:
			;wParam=TRUE/FALSE
			;lParam=0
			mov		eax,wParam
			mov		[ebx].EDIT.fHideSel,eax
			ret
		align 4 
		_EM_GETSELTEXT:
			;wParam=0
			;lParam=lpBuff
			invoke GetText,ebx,[ebx].EDIT.cpMin,[ebx].EDIT.cpMax,lParam,FALSE
			ret
		align 4 
		_EM_CANPASTE:
			;wParam=CF_TEXT
			;lParam=0
			invoke IsClipboardFormatAvailable,wParam
			ret
		align 4 
		_EM_STREAMIN:
			;wParam=SF_TEXT
			;lParam=lpStream
			invoke StreamIn,ebx,lParam
			xor		eax,eax
			mov		[ebx].EDIT.edta.cpy,eax
			mov		[ebx].EDIT.edta.cpxmax,eax
			mov		[ebx].EDIT.edta.topyp,eax
			mov		[ebx].EDIT.edta.topln,eax
			mov		[ebx].EDIT.edta.topcp,eax
			mov		[ebx].EDIT.edtb.cpy,eax
			mov		[ebx].EDIT.edtb.cpxmax,eax
			mov		[ebx].EDIT.edtb.topyp,eax
			mov		[ebx].EDIT.edtb.topln,eax
			mov		[ebx].EDIT.edtb.topcp,eax
			mov		[ebx].EDIT.cpMin,eax
			mov		[ebx].EDIT.cpMax,eax
			mov		[ebx].EDIT.blrg.lnMin,eax
			mov		[ebx].EDIT.blrg.clMin,eax
			mov		[ebx].EDIT.blrg.lnMax,eax
			mov		[ebx].EDIT.blrg.clMax,eax
			mov		[ebx].EDIT.line,eax
			mov		[ebx].EDIT.cpx,eax
			mov		[ebx].EDIT.cpLine,eax
			mov		[ebx].EDIT.rpLine,eax
			mov		[ebx].EDIT.rpChars,eax
			invoke GetCharPtr,ebx,0
			invoke InvalidateEdit,ebx,[ebx].EDIT.edta.hwnd
			invoke InvalidateEdit,ebx,[ebx].EDIT.edtb.hwnd
			invoke SetCaret,ebx,0
			invoke SelChange,ebx,SEL_TEXT
			inc		nUndoid
			xor		eax,eax
			ret
		align 4 
		_EM_STREAMOUT:
			;wParam=SF_TEXT
			;lParam=lpStream
			invoke StreamOut,ebx,lParam
			xor		eax,eax
			ret
		align 4 
		_EM_FORMATRANGE:
			mov		edi,lParam
			.if edi
				invoke GetStockObject,SYSTEM_FONT
				invoke SelectObject,[edi].FORMATRANGE.hdc,eax
				push	eax
				mov		edx,eax
				invoke GetObject,edx,sizeof lf,addr lf
				pop		eax
				invoke SelectObject,[edi].FORMATRANGE.hdc,eax
				invoke GetDeviceCaps,[edi].FORMATRANGE.hdc,LOGPIXELSY
				push	eax
				invoke GetDeviceCaps,[edi].FORMATRANGE.hdcTarget,LOGPIXELSY
				mov		ecx,eax
				mov		eax,lf.lfHeight
				.if sdword ptr eax<0
					neg		eax
				.endif
				mul		ecx
				pop		ecx
				xor		edx,edx
				div		ecx
				;neg		eax
				mov		lf.lfHeight,eax

				invoke GetDeviceCaps,[edi].FORMATRANGE.hdc,LOGPIXELSX
				push	eax
				invoke GetDeviceCaps,[edi].FORMATRANGE.hdcTarget,LOGPIXELSX
				mov		ecx,eax
				mov		eax,lf.lfWidth
				mul		ecx
				pop		ecx
				xor		edx,edx
				div		ecx
				mov		lf.lfWidth,eax
				invoke CreateFontIndirect,addr lf
				invoke SelectObject,[edi].FORMATRANGE.hdcTarget,eax
				push	eax
				;Get tab width
				mov		eax,57575757h ; 'WWWW'
				mov		pt.x,eax
				invoke GetTextExtentPoint32,[edi].FORMATRANGE.hdcTarget,addr pt.x,4,addr pt
				mov		eax,pt.x
				shr		eax,2
				mov		ecx,[ebx].EDIT.nTab
				mul		ecx
				mov		tabWt,eax
				invoke xGlobalAlloc,GMEM_FIXED,16384
				mov		esi,eax
				invoke ConvTwipsToPixels,[edi].FORMATRANGE.hdcTarget,TRUE,[edi].FORMATRANGE.rc.left
				mov		rect.left,eax
				invoke ConvTwipsToPixels,[edi].FORMATRANGE.hdcTarget,FALSE,[edi].FORMATRANGE.rc.top
				mov		rect.top,eax
				invoke ConvTwipsToPixels,[edi].FORMATRANGE.hdcTarget,TRUE,[edi].FORMATRANGE.rc.right
				mov		rect.right,eax
				invoke ConvTwipsToPixels,[edi].FORMATRANGE.hdcTarget,FALSE,[edi].FORMATRANGE.rc.bottom
				mov		rect.bottom,eax
				invoke CreateRectRgn,rect.left,rect.top,rect.right,rect.bottom
				invoke SelectObject,[edi].FORMATRANGE.hdcTarget,eax
				push	eax
				invoke SendMessage,hWin,EM_LINEFROMCHAR,[edi].FORMATRANGE.chrg.cpMin,0
				mov		nLine,eax
			  @@:
				mov		word ptr [esi],16383
				invoke SendMessage,hWin,EM_GETLINE,nLine,esi
				mov		len,eax
				mov		eax,rect.top
				add		eax,pt.y
				.if eax<rect.bottom
					.if wParam
						invoke TabbedTextOut,[edi].FORMATRANGE.hdcTarget,rect.left,rect.top,esi,len,1,addr tabWt,rect.left
					.endif
					mov		eax,pt.y
					add		rect.top,eax
					inc		nLine
					invoke SendMessage,hWin,EM_LINEINDEX,nLine,0
					.if eax<[edi].FORMATRANGE.chrg.cpMax
						jmp		@b
					.endif
				.endif
				invoke GlobalFree,esi
				pop		eax
				invoke SelectObject,[edi].FORMATRANGE.hdcTarget,eax
				invoke DeleteObject,eax
				pop		eax
				invoke SelectObject,[edi].FORMATRANGE.hdcTarget,eax
				invoke DeleteObject,eax
				invoke SendMessage,hWin,EM_LINEINDEX,nLine,0
			.endif
			ret
		align 4
		_DefRichEditMsg:
			invoke DefWindowProc,hWin,uMsg,wParam,lParam
			ret

.data
align 4
_RICHEDIT_MSG \
	dd _EM_CANPASTE				;(1024+50)
	dd _DefRichEditMsg			;(1024+51) _EM_DISPLAYBAND			<- DefWindowProc
	dd _EM_EXGETSEL				;(1024+52)
	dd _DefRichEditMsg			;(1024+53) _EM_EXLIMITTEXT			<- DefWindowProc
	dd _EM_EXLINEFROMCHAR		;(1024+54)
	dd _EM_EXSETSEL				;(1024+55)
	dd _DefRichEditMsg			;(1024+56) _EM_FINDTEXT				<- DefWindowProc
	dd _EM_FORMATRANGE			;(1024+57)
	dd _DefRichEditMsg			;(1024+58) _EM_GETCHARFORMAT		<- DefWindowProc
	dd _DefRichEditMsg			;(1024+59) _EM_GETEVENTMASK			<- DefWindowProc
	dd _DefRichEditMsg			;(1024+60) _EM_GETOLEINTERFACE		<- DefWindowProc
	dd _DefRichEditMsg			;(1024+61) _EM_GETPARAFORMAT		<- DefWindowProc
	dd _EM_GETSELTEXT			;(1024+62)
	dd _EM_HIDESELECTION		;(1024+63)
	dd _DefRichEditMsg			;(1024+64) _EM_PASTESPECIAL			<- DefWindowProc
	dd _DefRichEditMsg			;(1024+65) _EM_REQUESTRESIZE		<- DefWindowProc
	dd _DefRichEditMsg			;(1024+66) _EM_SELECTIONTYPE		<- DefWindowProc
	dd _DefRichEditMsg			;(1024+67) _EM_SETBKGNDCOLOR		<- DefWindowProc
	dd _DefRichEditMsg			;(1024+68) _EM_SETCHARFORMAT		<- DefWindowProc
	dd _DefRichEditMsg			;(1024+69) _EM_SETEVENTMASK			<- DefWindowProc
	dd _DefRichEditMsg			;(1024+70) _EM_SETOLECALLBACK		<- DefWindowProc
	dd _DefRichEditMsg			;(1024+71) _EM_SETPARAFORMAT		<- DefWindowProc
	dd _DefRichEditMsg			;(1024+72) _EM_SETTARGETDEVICE		<- DefWindowProc
	dd _EM_STREAMIN				;(1024+73)
	dd _EM_STREAMOUT			;(1024+74)
	dd _EM_GETTEXTRANGE			;(1024+75)
	dd _EM_FINDWORDBREAK		;(1024+76)
	dd _DefRichEditMsg			;(1024+77) _EM_SETOPTIONS			<- DefWindowProc
	dd _DefRichEditMsg			;(1024+78) _EM_GETOPTIONS			<- DefWindowProc
	dd _EM_FINDTEXTEX			;(1024+79)
	dd _DefRichEditMsg			;(1024+80) _EM_GETWORDBREAKPROCEX	<- DefWindowProc
	dd _DefRichEditMsg			;(1024+81) _EM_SETWORDBREAKPROCEX	<- DefWindowProc
	dd _DefRichEditMsg			;(1024+82) _EM_SETUNDOLIMIT			<- DefWindowProc
	dd _DefRichEditMsg			;(1024+83) _UNKNOW_MSG				<- DefWindowProc
	dd _EM_REDO					;(1024+84)
	dd _EM_CANREDO				;(1024+85)

.code
align 4
		;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
		; END OF: RAEdit_Richedit_Msg_JumpTable.asm
	.endif
	.if eax>=EM_GETSEL && eax<=EM_GETIMESTATUS
		sub		eax,EM_GETSEL
		jmp		DWORD PTR [offset _EDIT_MSG+eax*4]
		; RAEdit_Edit_Msg_JumpTable.asm
		;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
		align 4 
		_EM_CHARFROMPOS:
			;wParam=0
			;lParam=lpPoint
			mov		edx,lParam
			invoke GetCharFromPos,ebx,[esi].RAEDT.cpy,[edx].POINT.x,[edx].POINT.y
			ret
		align 4 
		_EM_POSFROMCHAR:
			;wParam=lpPoint
			;lParam=cp
			invoke GetPosFromChar,ebx,lParam,wParam
			mov		edx,wParam
			mov		eax,[ebx].EDIT.cpx
			sub		[edx].POINT.x,eax
			mov		eax,[esi].RAEDT.cpy
			sub		[edx].POINT.y,eax
			xor		eax,eax
			ret
		align 4 
		_EM_LINEFROMCHAR:
			;wParam=cp
			;lParam=0
			mov		eax,wParam
			.if eax==-1
				mov		eax,[ebx].EDIT.cpMin
			.endif
			invoke GetCharPtr,ebx,eax
			mov		eax,edx
			ret
		align 4 
		_EM_LINEINDEX:
			;wParam=line
			;lParam=0
			mov		eax,wParam
			.if eax==-1
				mov		eax,[ebx].EDIT.line
			.endif
			invoke GetCpFromLine,ebx,eax
			ret
		align 4 
		_EM_GETLINE:
			;wParam=line
			;lParam=lpBuff
			mov		edx,wParam
			shl		edx,2
			.if edx<[ebx].EDIT.rpLineFree
				add		edx,[ebx].EDIT.hLine
				mov		edx,[edx].LINE.rpChars
				add		edx,[ebx].EDIT.hChars
				mov		ecx,[edx].CHARS.len
				.if byte ptr [edx+ecx+sizeof CHARS-1]==VK_RETURN && ecx
					dec		ecx
				.endif
				mov		edi,lParam
				.if cx>word ptr [edi]
					movzx	ecx,word ptr [edi]
				.endif
				push	ecx
				lea		esi,[edx+sizeof CHARS]
				rep movsb
				pop		eax
			.else
				xor		eax,eax
			.endif
			ret
		align 4 
		_EM_LINELENGTH:
			;wParam=cp
			;lParam=0
			invoke GetLineFromCp,ebx,wParam
			mov		edx,eax
			shl		edx,2
			add		edx,[ebx].EDIT.hLine
			mov		edx,[edx].LINE.rpChars
			add		edx,[ebx].EDIT.hChars
			mov		eax,[edx].CHARS.len
			.if eax
				.if byte ptr [edx+eax+sizeof CHARS-1]==0Dh
					dec		eax
				.endif
			.endif
			ret
		align 4 
		_EM_GETFIRSTVISIBLELINE:
			;wParam=0
			;lParam=0
			mov		eax,[esi].RAEDT.topln
			ret
		align 4 
		_EM_LINESCROLL:
			;wParam=cxScroll
			;lParam=cyScroll
			mov		eax,wParam
			mov		edx,[ebx].EDIT.fntinfo.fntwt
			.if sdword ptr eax<0
				neg		eax
				mul		edx
				neg		eax
			.else
				mul		edx
			.endif
			add		eax,[ebx].EDIT.cpx
			mov		[ebx].EDIT.cpx,eax
			mov		eax,lParam
			mov		edx,[ebx].EDIT.fntinfo.fntht
			.if sdword ptr eax<0
				neg		eax
				mul		edx
				neg		eax
			.else
				mul		edx
			.endif
			add		eax,[esi].RAEDT.cpy
			.if sdword ptr eax<0
				xor		eax,eax
			.endif
			mov		[esi].RAEDT.cpy,eax
			invoke InvalidateEdit,ebx,[esi].RAEDT.hwnd
			mov		eax,TRUE
			ret
		align 4 
		_EM_SCROLLCARET:
			;wParam=0
			;lParam=0
			invoke SetCaretVisible,[esi].RAEDT.hwnd,[esi].RAEDT.cpy
			invoke SetCaret,ebx,[esi].RAEDT.cpy
			mov		eax,TRUE
			ret
		align 4 
		_EM_SETSEL:
			;wParam=cpMin
			;lParam=cpMax
			.if !([ebx].EDIT.nMode&MODE_BLOCK)
				.if ![ebx].EDIT.fHideSel
					mov		eax,[ebx].EDIT.cpMin
					.if eax!=[ebx].EDIT.cpMax
						invoke InvalidateSelection,ebx,[ebx].EDIT.edta.hwnd,[ebx].EDIT.cpMin,[ebx].EDIT.cpMax
						invoke InvalidateSelection,ebx,[ebx].EDIT.edtb.hwnd,[ebx].EDIT.cpMin,[ebx].EDIT.cpMax
					.endif
				.endif
				invoke GetCharPtr,ebx,lParam
				mov		[ebx].EDIT.cpMax,ecx
				invoke GetCharPtr,ebx,wParam
				mov		[ebx].EDIT.cpMin,ecx
				.if ![ebx].EDIT.fHideSel
					invoke TestExpand,ebx,[ebx].EDIT.line
					mov		eax,[ebx].EDIT.cpMin
					.if eax!=[ebx].EDIT.cpMax
						invoke InvalidateSelection,ebx,[ebx].EDIT.edta.hwnd,[ebx].EDIT.cpMin,[ebx].EDIT.cpMax
						invoke InvalidateSelection,ebx,[ebx].EDIT.edtb.hwnd,[ebx].EDIT.cpMin,[ebx].EDIT.cpMax
						invoke SetCaret,ebx,[esi].RAEDT.cpy
						invoke SetCpxMax,ebx,[esi].RAEDT.hwnd
					.endif
				.endif
				invoke SelChange,ebx,SEL_TEXT
			.endif
			xor		eax,eax
			ret
		align 4 
		_EM_GETSEL:
			;wParam=lpcpMin
			;lParam=lpcpMax
			mov		eax,[ebx].EDIT.cpMin
			mov		ecx,[ebx].EDIT.cpMax
			.if eax>ecx
				xchg	eax,ecx
			.endif
			mov		edx,wParam
			.if edx
				mov		[edx],eax
			.endif
			mov		edx,lParam
			.if edx
				mov		[edx],ecx
			.endif
			and		eax,0FFFFh
			shl		ecx,16
			or		eax,ecx
			ret
		align 4 
		_EM_GETMODIFY:
			;wParam=0
			;lParam=0
			mov		eax,[ebx].EDIT.fChanged
			ret
		align 4 
		_EM_SETMODIFY:
			;wParam=TRUE/FALSE
			;lParam=0
			mov		eax,wParam
			mov		[ebx].EDIT.fChanged,eax
			invoke InvalidateRect,[ebx].EDIT.hsta,NULL,TRUE
			ret
		align 4 
		_EM_REPLACESEL:
			;wParam=TRUE/FALSE
			;lParam=lpText
			.if !wParam
				inc		fNoSaveUndo
			.endif
			invoke IsSelectionLocked,ebx,[ebx].EDIT.cpMin,[ebx].EDIT.cpMax
			.if eax!=0
				jmp		ErrBeep
			.endif
			inc		nUndoid
			invoke DeleteSelection,ebx,[ebx].EDIT.cpMin,[ebx].EDIT.cpMax
			mov		[ebx].EDIT.cpMin,eax
			mov		[ebx].EDIT.cpMax,eax
			push	eax
			push	[ebx].EDIT.fOvr
			mov		[ebx].EDIT.fOvr,0
			invoke EditInsert,ebx,[ebx].EDIT.cpMin,lParam
			pop		[ebx].EDIT.fOvr
			pop		ecx
			add		[ebx].EDIT.cpMin,eax
			add		[ebx].EDIT.cpMax,eax
			.if wParam && eax
				invoke SaveUndo,ebx,UNDO_INSERTBLOCK,ecx,lParam,eax
			.endif
			invoke GetCharPtr,ebx,[ebx].EDIT.cpMin
			invoke SetCaretVisible,[esi].RAEDT.hwnd,[esi].RAEDT.cpy
			invoke SetCaret,ebx,[esi].RAEDT.cpy
			invoke InvalidateEdit,ebx,[ebx].EDIT.edta.hwnd
			invoke InvalidateEdit,ebx,[ebx].EDIT.edtb.hwnd
			invoke SetCpxMax,ebx,[esi].RAEDT.hwnd
			invoke SelChange,ebx,SEL_TEXT
			inc		nUndoid
			xor		eax,eax
			mov		fNoSaveUndo,eax
			ret
		align 4 
		_EM_GETLINECOUNT:
			;wParam=0
			;lParam=0
			mov		eax,[ebx].EDIT.rpLineFree
			shr		eax,2
			dec		eax
			ret
		align 4 
		_EM_GETRECT:
			;wParam=0
			;lParam=lpRECT
			mov		edx,lParam
			mov		eax,[esi].RAEDT.rc.left
			mov		[edx].RECT.left,eax
			mov		eax,[esi].RAEDT.rc.top
			mov		[edx].RECT.top,eax
			mov		eax,[esi].RAEDT.rc.right
			mov		[edx].RECT.right,eax
			mov		eax,[esi].RAEDT.rc.bottom
			mov		[edx].RECT.bottom,eax
			mov		eax,[ebx].EDIT.focus
			.if eax==[ebx].EDIT.edtb.hwnd && [ebx].EDIT.nsplitt
				mov		eax,[ebx].EDIT.nsplitt
				add		eax,BTNHT
				add		[edx].RECT.top,eax
				add		[edx].RECT.bottom,eax
			.endif
			ret
		align 4 
		_EM_CANUNDO:
			;wParam=0
			;lParam=0
			xor		eax,eax
			.if !([ebx].EDIT.nMode&MODE_BLOCK)
				mov		eax,[ebx].EDIT.rpUndo
				.if eax
					mov		eax,TRUE
				.endif
			.endif
			ret
		align 4 
		_EM_UNDO:
			;wParam=0
			;lParam=0
			inc		nUndoid
			invoke Undo,ebx,[esi].RAEDT.hwnd
			inc		nUndoid
			ret
		align 4 
		_EM_EMPTYUNDOBUFFER:
			;wParam=0
			;lParam=0
			mov		edi,[ebx].EDIT.hUndo
			mov		ecx,[ebx].EDIT.cbUndo
			xor		eax,eax
			mov		[ebx].EDIT.rpUndo,eax
			rep stosb
			inc		nUndoid
			ret
		align 4
		_DefEditMsg:
			invoke DefWindowProc,hWin,uMsg,wParam,lParam
			ret

.data
align 4
_EDIT_MSG \
	dd _EM_GETSEL				;0x00B0
	dd _EM_SETSEL				;0x00B1
	dd _EM_GETRECT				;0x00B2
	dd _DefEditMsg				;0x00B3 _EM_SETRECT					<- DefWindowProc
	dd _DefEditMsg				;0x00B4 _EM_SETRECTNP				<- DefWindowProc
	dd _DefEditMsg				;0x00B5 _EM_SCROLL					<- DefWindowProc
	dd _EM_LINESCROLL			;0x00B6
	dd _EM_SCROLLCARET			;0x00B7
	dd _EM_GETMODIFY			;0x00B8
	dd _EM_SETMODIFY			;0x00B9
	dd _EM_GETLINECOUNT			;0x00BA
	dd _EM_LINEINDEX			;0x00BB
	dd _DefEditMsg				;0x00BC _EM_SETHANDLE				<- DefWindowProc
	dd _DefEditMsg				;0x00BD _EM_GETHANDLE				<- DefWindowProc
	dd _DefEditMsg				;0x00BE _EM_GETTHUMB				<- DefWindowProc
	dd _DefEditMsg				;0x00BF _UNKNOW_MSG					<- DefWindowProc
	dd _DefEditMsg				;0x00C0 _UNKNOW_MSG					<- DefWindowProc
	dd _EM_LINELENGTH			;0x00C1
	dd _EM_REPLACESEL			;0x00C2
	dd _DefEditMsg				;0x00C3 _UNKNOW_MSG					<- DefWindowProc
	dd _EM_GETLINE				;0x00C4
	dd _DefEditMsg				;0x00C5 _EM_LIMITTEXT				<- DefWindowProc
	dd _EM_CANUNDO				;0x00C6
	dd _EM_UNDO					;0x00C7
	dd _DefEditMsg				;0x00C8 _EM_FMTLINES				<- DefWindowProc
	dd _EM_LINEFROMCHAR			;0x00C9
	dd _DefEditMsg				;0x00CA _UNKNOW_MSG					<- DefWindowProc
	dd _DefEditMsg				;0x00CB _EM_SETTABSTOPS				<- DefWindowProc
	dd _DefEditMsg				;0x00CC _EM_SETPASSWORDCHAR			<- DefWindowProc
	dd _EM_EMPTYUNDOBUFFER		;0x00CD
	dd _EM_GETFIRSTVISIBLELINE	;0x00CE
	dd _DefEditMsg				;0x00CF _EM_SETREADONLY				<- DefWindowProc
	dd _DefEditMsg				;0x00D0 _EM_SETWORDBREAKPROC		<- DefWindowProc
	dd _DefEditMsg				;0x00D1 _EM_GETWORDBREAKPROC		<- DefWindowProc
	dd _DefEditMsg				;0x00D2 _EM_GETPASSWORDCHAR			<- DefWindowProc
	dd _DefEditMsg				;0x00D3 _EM_SETMARGINS				<- DefWindowProc
	dd _DefEditMsg				;0x00D4 _EM_GETMARGINS				<- DefWindowProc
	dd _DefEditMsg				;0x00D5 _EM_GETLIMITTEXT			<- DefWindowProc
	dd _EM_POSFROMCHAR			;0x00D6
	dd _EM_CHARFROMPOS			;0x00D7
	dd _DefEditMsg				;0x00D8 _EM_SETIMESTATUS			<- DefWindowProc
	dd _DefEditMsg				;0x00D9 _EM_GETIMESTATUS			<- DefWindowProc
	;dd _EM_SETLIMITTEXT		;EM_LIMITTEXT   /* ;win40 Name change */

.code
align 4
		;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
		; END OF: RAEdit_Edit_Msg_JumpTable.asm
	.endif
	.if eax==WM_COPY
		;wParam=0
		;lParam=0
		invoke Copy,ebx
		xor		eax,eax
		jmp		Ex
	.elseif eax==WM_CUT
		;wParam=0
		;lParam=0
		inc		nUndoid
		invoke Cut,ebx,[esi].RAEDT.hwnd
		inc		nUndoid
		jmp		Ex
	.elseif eax==WM_PASTE
		;wParam=0
		;lParam=0
		invoke IsSelectionLocked,ebx,[ebx].EDIT.cpMin,[ebx].EDIT.cpMax
		.if eax!=0
			jmp		ErrBeep
		.endif
		inc		nUndoid
		invoke Paste,ebx,[esi].RAEDT.hwnd,NULL
		inc		nUndoid
		xor		eax,eax
		jmp		Ex
	.elseif eax==WM_CLEAR
		;wParam=0
		;lParam=0
		invoke IsSelectionLocked,ebx,[ebx].EDIT.cpMin,[ebx].EDIT.cpMax
		.if eax!=0
			jmp		ErrBeep
		.endif
		inc		nUndoid
		.if !([ebx].EDIT.nMode&MODE_BLOCK)
			invoke DeleteSelection,ebx,[ebx].EDIT.cpMin,[ebx].EDIT.cpMax
			mov		[ebx].EDIT.cpMin,eax
			mov		[ebx].EDIT.cpMax,eax
			invoke GetCharPtr,ebx,[ebx].EDIT.cpMin
			invoke SetCaretVisible,hWin,[esi].RAEDT.cpy
			invoke SetCaret,ebx,[esi].RAEDT.cpy
			invoke InvalidateRect,[ebx].EDIT.edta.hwnd,NULL,FALSE
			invoke InvalidateRect,[ebx].EDIT.edtb.hwnd,NULL,FALSE
		.else
			invoke DeleteSelectionBlock,ebx,[ebx].EDIT.blrg.lnMin,[ebx].EDIT.blrg.clMin,[ebx].EDIT.blrg.lnMax,[ebx].EDIT.blrg.clMax
			mov		eax,[ebx].EDIT.blrg.clMin
			.if eax>[ebx].EDIT.blrg.clMax
				mov		eax,[ebx].EDIT.blrg.clMax
			.endif
			mov		edx,[ebx].EDIT.blrg.lnMin
			.if edx>[ebx].EDIT.blrg.lnMax
				mov		edx,[ebx].EDIT.blrg.lnMax
			.endif
			mov		[ebx].EDIT.blrg.clMin,eax
			mov		[ebx].EDIT.blrg.lnMin,edx
			mov		[ebx].EDIT.blrg.clMax,eax
			mov		[ebx].EDIT.blrg.lnMax,edx
			invoke GetBlockCp,ebx,edx,eax
			mov		[ebx].EDIT.cpMin,eax
			mov		[ebx].EDIT.cpMax,eax
			invoke GetCharPtr,ebx,[ebx].EDIT.cpMin
			invoke SetCaretVisible,hWin,[esi].RAEDT.cpy
			invoke SetCaret,ebx,[esi].RAEDT.cpy
			invoke InvalidateEdit,ebx,[ebx].EDIT.edta.hwnd
			invoke InvalidateEdit,ebx,[ebx].EDIT.edtb.hwnd
		.endif
		invoke SetCpxMax,ebx,[esi].RAEDT.hwnd
		invoke SelChange,ebx,SEL_TEXT
		inc		nUndoid
		xor		eax,eax
		jmp		Ex
	.elseif eax==WM_SETTEXT
		;wParam=0
		;lParam=lpszText
		call	NestedProc_RelMem
		call	NestedProc_AllocMem
		invoke EditInsert,ebx,0,lParam
		xor		eax,eax
		mov		[ebx].EDIT.edta.cpy,eax
		mov		[ebx].EDIT.edta.cpxmax,eax
		mov		[ebx].EDIT.edta.topyp,eax
		mov		[ebx].EDIT.edta.topln,eax
		mov		[ebx].EDIT.edta.topcp,eax
		mov		[ebx].EDIT.edtb.cpy,eax
		mov		[ebx].EDIT.edtb.cpxmax,eax
		mov		[ebx].EDIT.edtb.topyp,eax
		mov		[ebx].EDIT.edtb.topln,eax
		mov		[ebx].EDIT.edtb.topcp,eax
		mov		[ebx].EDIT.cpMin,eax
		mov		[ebx].EDIT.cpMax,eax
		mov		[ebx].EDIT.blrg.lnMin,eax
		mov		[ebx].EDIT.blrg.clMin,eax
		mov		[ebx].EDIT.blrg.lnMax,eax
		mov		[ebx].EDIT.blrg.clMax,eax
		mov		[ebx].EDIT.line,eax
		mov		[ebx].EDIT.cpx,eax
		mov		[ebx].EDIT.cpLine,eax
		mov		[ebx].EDIT.rpLine,eax
		mov		[ebx].EDIT.rpChars,eax
		invoke GetCharPtr,ebx,0
		invoke InvalidateEdit,ebx,[ebx].EDIT.edta.hwnd
		invoke InvalidateEdit,ebx,[ebx].EDIT.edtb.hwnd
		invoke SetCaret,ebx,0
		invoke SelChange,ebx,SEL_TEXT
		inc		nUndoid
		mov		eax,TRUE
		jmp		Ex
	.elseif eax==WM_GETTEXT
		;wParam=cbBuff
		;lParam=lpBuff
		mov		eax,wParam
		mov		edi,lParam
		.if eax
			mov		chrg.cpMin,0
			dec		eax
			mov		chrg.cpMax,eax
			mov		edx,[ebx].EDIT.hLine
			mov		eax,edx
			add		eax,[ebx].EDIT.rpLineFree
			.while edx<eax
				mov		esi,[edx].LINE.rpChars
				add		esi,[ebx].EDIT.hChars
				mov		ecx,[esi].CHARS.len
				add		esi,sizeof CHARS
				.if ecx>chrg.cpMax
					mov		ecx,chrg.cpMax
					add		chrg.cpMin,ecx
					rep movsb
					.break
				.endif
				add		chrg.cpMin,ecx
				rep movsb
				add		edx,sizeof LINE
			.endw
			mov		byte ptr [edi],0
			mov		eax,chrg.cpMin
		.endif
		jmp		Ex
	.elseif eax==WM_GETTEXTLENGTH
		;wParam=0
		;lParam=0
		mov		edx,[ebx].EDIT.hLine
		mov		edi,edx
		add		edi,[ebx].EDIT.rpLineFree
		mov		eax,[esi].RAEDT.topln
		shl		eax,2
		add		edx,eax
		mov		eax,[esi].RAEDT.topcp
		.while edx<edi
			mov		ecx,[edx].LINE.rpChars
			add		ecx,[ebx].EDIT.hChars
			add		eax,[ecx].CHARS.len
			add		edx,sizeof LINE
		.endw
		jmp		Ex
	.elseif eax==WM_MOUSEMOVE
		;Get mouse position
		mov		eax,lParam
		mov		edx,eax
		and		eax,0FFFFh
		shr		edx,16
		.if [ebx].EDIT.fresize==1
			mov		[ebx].EDIT.fresize,2
		.elseif [ebx].EDIT.fresize==2
			mov		eax,lParam
			shr		eax,16
			cwde
			sub		eax,2
			mov		edx,[ebx].EDIT.rc.bottom
			sub		edx,30
			.if sdword ptr eax<0
				xor		eax,eax
			.elseif sdword ptr eax>edx
				mov		eax,edx
			.endif
			.if eax
				shl		eax,10
				mov		ecx,[ebx].EDIT.rc.bottom
				xor		edx,edx
				div		ecx
			.endif
			mov		[ebx].EDIT.fsplitt,eax
			call	NestedProc_SizeIt
			invoke UpdateWindow,[ebx].EDIT.hsbtn
			invoke UpdateWindow,[ebx].EDIT.edta.hwnd
			invoke UpdateWindow,[ebx].EDIT.edtb.hwnd
		.endif
		xor		eax,eax
		jmp		Ex
	.elseif eax==WM_LBUTTONDOWN
		xor		eax,eax
		jmp		Ex
	.elseif eax==WM_LBUTTONUP
		.if [ebx].EDIT.fresize
			mov		[ebx].EDIT.fresize,0
			invoke ReleaseCapture
			call	NestedProc_SizeIt
			.if [ebx].EDIT.fsplitt==0
				invoke SetFocus,[ebx].EDIT.edtb.hwnd
			.endif
		.endif
		xor		eax,eax
		jmp		Ex
	.elseif eax==WM_LBUTTONDBLCLK
		xor		eax,eax
		jmp		Ex
	.elseif eax==WM_CREATE
		invoke GetSystemMetrics,SM_CXVSCROLL
		mov		SBWT,eax
		;Allocate memory for the edit control
		invoke GetProcessHeap
		mov		edx,sizeof EDIT
		shr		edx,3
		inc		edx
		shl		edx,3
		invoke xHeapAlloc,eax,HEAP_GENERATE_EXCEPTIONS or HEAP_ZERO_MEMORY,edx
		mov		ebx,eax
		;Save the pointer
		invoke SetWindowLong,hWin,0,ebx
		mov		eax,hWin
		mov		[ebx].EDIT.hwnd,eax
		invoke GetParent,eax
		mov		[ebx].EDIT.hpar,eax
		invoke GetWindowLong,hWin,GWL_STYLE
		mov		[ebx].EDIT.fstyle,eax
		invoke GetWindowLong,[ebx].EDIT.hwnd,GWL_ID
		mov		[ebx].EDIT.ID,eax
		call	NestedProc_AllocMem
		mov		[ebx].EDIT.nlinenrwt,LNRWT
		mov		[ebx].EDIT.linenrwt,0
		mov		[ebx].EDIT.selbarwt,SELWT
		mov		[ebx].EDIT.fIndent,TRUE
		mov		[ebx].EDIT.nTab,4
		mov		[ebx].EDIT.nScroll,3
		mov		[ebx].EDIT.fntinfo.fntht,10
		mov		[ebx].EDIT.clr.bckcol,BCKCLR
		mov		[ebx].EDIT.clr.txtcol,TXTCLR
		mov		[ebx].EDIT.clr.selbckcol,SELBCKCLR
		mov		[ebx].EDIT.clr.seltxtcol,SELTXTCLR
		mov		[ebx].EDIT.clr.cmntcol,CMNTCLR
		mov		[ebx].EDIT.clr.strcol,STRCLR
		mov		[ebx].EDIT.clr.oprcol,OPRCLR
		mov		[ebx].EDIT.clr.hicol1,HILITE1
		mov		[ebx].EDIT.clr.hicol2,HILITE2
		mov		[ebx].EDIT.clr.hicol3,HILITE3
		mov		[ebx].EDIT.clr.selbarbck,SELBARCLR
		mov		[ebx].EDIT.clr.selbarpen,SELBARPEN
		mov		[ebx].EDIT.clr.lnrcol,LNRCLR
		mov		[ebx].EDIT.clr.numcol,NUMCLR
		mov		[ebx].EDIT.clr.cmntback,CMNTBCK
		mov		[ebx].EDIT.clr.strback,STRBCK
		mov		[ebx].EDIT.clr.numback,NUMBCK
		mov		[ebx].EDIT.clr.oprback,OPRBCK
		mov		[ebx].EDIT.clr.changed,CHANGEDCLR
		mov		[ebx].EDIT.clr.changesaved,CHANGESAVEDCLR
		invoke CreateBrushes,ebx

		invoke CreateWindowEx,NULL,addr szToolTips,NULL,TTS_ALWAYSTIP,CW_USEDEFAULT,CW_USEDEFAULT,CW_USEDEFAULT,CW_USEDEFAULT,NULL,NULL,hInstance,NULL
		mov		[ebx].EDIT.htt,eax

		invoke CreateWindowEx,1,addr szStatic,NULL,SS_NOTIFY or WS_CHILD or WS_VISIBLE,0,0,0,0,hWin,-1,hInstance,0
		mov		[ebx].EDIT.hsbtn,eax
		mov		edx,offset szSplitterBar
		call	NestedProc_SetToolTip
		invoke SetWindowLong,[ebx].EDIT.hsbtn,GWL_WNDPROC,addr SplittBtnProc
		mov		OldSplittBtnProc,eax

		invoke CreateWindowEx,NULL,addr szEditClassName,NULL,WS_CLIPSIBLINGS or WS_CHILD or WS_VISIBLE,0,0,0,0,hWin,NULL,hInstance,0
		mov		[ebx].EDIT.edta.hwnd,eax
		invoke CreateWindowEx,NULL,addr szScrollBar,NULL,WS_CHILD or WS_VISIBLE or SBS_VERT,0,0,0,0,[ebx].EDIT.edta.hwnd,NULL,hInstance,0
		mov		[ebx].EDIT.edta.hvscroll,eax

		invoke CreateWindowEx,NULL,addr szEditClassName,NULL,WS_CLIPSIBLINGS or WS_CHILD or WS_VISIBLE,0,0,0,0,hWin,NULL,hInstance,0
		mov		[ebx].EDIT.edtb.hwnd,eax
		invoke CreateWindowEx,NULL,addr szScrollBar,NULL,WS_CHILD or WS_VISIBLE or SBS_VERT,0,0,0,0,[ebx].EDIT.edtb.hwnd,NULL,hInstance,0
		mov		[ebx].EDIT.edtb.hvscroll,eax

		invoke CreateWindowEx,NULL,addr szScrollBar,NULL,WS_CHILD or WS_VISIBLE or SBS_HORZ,0,0,0,0,hWin,NULL,hInstance,0
		mov		[ebx].EDIT.hhscroll,eax
		invoke CreateWindowEx,NULL,addr szScrollBar,NULL,WS_CHILD or WS_VISIBLE or SBS_SIZEGRIP,0,0,0,0,hWin,NULL,hInstance,0
		mov		[ebx].EDIT.hgrip,eax

		invoke CreateWindowEx,NULL,addr szStatic,NULL,WS_CHILD or WS_VISIBLE,0,0,0,0,hWin,NULL,hInstance,0
		mov		[ebx].EDIT.hnogrip,eax

		invoke CreateWindowEx,NULL,addr szStatic,NULL,SS_NOTIFY or WS_CHILD or WS_VISIBLE,0,0,0,0,hWin,NULL,hInstance,0
		mov		[ebx].EDIT.hsta,eax
		mov		edx,offset szChanged
		call	NestedProc_SetToolTip
		invoke SetWindowLong,[ebx].EDIT.hsta,GWL_USERDATA,ebx
		invoke SetWindowLong,[ebx].EDIT.hsta,GWL_WNDPROC,addr StateProc
		mov		OldStateProc,eax

		invoke CreateWindowEx,NULL,addr szStatic,NULL,WS_POPUP or WS_BORDER or SS_OWNERDRAW,0,0,0,0,hWin,NULL,hInstance,0
		mov		[ebx].EDIT.htlt,eax

		invoke SetWindowLong,eax,GWL_WNDPROC,offset FakeToolTipProc
		mov		OldFakeToolTipProc,eax
		invoke SendMessage,[ebx].EDIT.htt,WM_GETFONT,0,0
		invoke SendMessage,[ebx].EDIT.htlt,WM_SETFONT,eax,FALSE

		invoke CreateWindowEx,NULL,addr szButton,NULL,BS_BITMAP or BS_PUSHLIKE or BS_AUTOCHECKBOX or WS_CHILD or WS_VISIBLE,0,0,0,0,hWin,-2,hInstance,0
		mov		[ebx].EDIT.hlin,eax
		mov		edx,offset szLineNumber
		call	NestedProc_SetToolTip
		invoke SendMessage,[ebx].EDIT.hlin,BM_SETIMAGE,IMAGE_BITMAP,hBmpLnr

		invoke CreateWindowEx,NULL,addr szButton,NULL,BS_BITMAP or BS_PUSHBUTTON or WS_CHILD or WS_VISIBLE,0,0,0,0,hWin,-3,hInstance,0
		mov		[ebx].EDIT.hexp,eax
		mov		edx,offset szExpand
		call	NestedProc_SetToolTip
		invoke SendMessage,[ebx].EDIT.hexp,BM_SETIMAGE,IMAGE_BITMAP,hBmpExp

		invoke CreateWindowEx,NULL,addr szButton,NULL,BS_BITMAP or BS_PUSHBUTTON or WS_CHILD or WS_VISIBLE,0,0,0,0,hWin,-4,hInstance,0
		mov		[ebx].EDIT.hcol,eax
		mov		edx,offset szCollapse
		call	NestedProc_SetToolTip
		invoke SendMessage,[ebx].EDIT.hcol,BM_SETIMAGE,IMAGE_BITMAP,hBmpCol

		invoke CreateWindowEx,NULL,addr szButton,NULL,BS_BITMAP or BS_PUSHLIKE or BS_AUTOCHECKBOX or WS_CHILD or WS_VISIBLE,0,0,0,0,hWin,-5,hInstance,0
		mov		[ebx].EDIT.hlock,eax
		mov		edx,offset szLock
		call	NestedProc_SetToolTip
		invoke SendMessage,[ebx].EDIT.hlock,BM_SETIMAGE,IMAGE_BITMAP,hBmpLck

		invoke SetWindowPos,[ebx].EDIT.hsta,HWND_TOP,0,0,0,0,SWP_NOSIZE or SWP_NOSIZE;SWP_NOREPOSITION
		invoke SetWindowPos,[ebx].EDIT.hsbtn,HWND_TOP,0,0,0,0,SWP_NOSIZE or SWP_NOSIZE;SWP_NOREPOSITION
		.if [ebx].EDIT.fstyle&STYLE_DRAGDROP
			invoke RegisterDragDrop,[ebx].EDIT.edta.hwnd,offset pIDropTarget
			invoke RegisterDragDrop,[ebx].EDIT.edtb.hwnd,offset pIDropTarget
		.endif
	.elseif eax==WM_DESTROY
		.if [ebx].EDIT.fstyle&STYLE_DRAGDROP
			invoke RevokeDragDrop,[ebx].EDIT.edta.hwnd
			invoke RevokeDragDrop,[ebx].EDIT.edtb.hwnd
		.endif
		invoke SetWindowLong,hWin,0,0
		invoke DestroyWindow,[ebx].EDIT.htt
		invoke DestroyWindow,[ebx].EDIT.hsbtn
		invoke DestroyWindow,[ebx].EDIT.edta.hvscroll
		invoke DestroyWindow,[ebx].EDIT.edtb.hvscroll
		invoke DestroyWindow,[ebx].EDIT.hhscroll
		invoke DestroyWindow,[ebx].EDIT.hgrip
		invoke DestroyWindow,[ebx].EDIT.hnogrip
		invoke DestroyWindow,[ebx].EDIT.hsta
		invoke DestroyWindow,[ebx].EDIT.hlin
		invoke DestroyWindow,[ebx].EDIT.hexp
		invoke DestroyWindow,[ebx].EDIT.hcol
		invoke DestroyWindow,[ebx].EDIT.hlock
		invoke DestroyWindow,[ebx].EDIT.edta.hwnd
		invoke DestroyWindow,[ebx].EDIT.edtb.hwnd
		invoke DestroyBrushes,ebx
		;Free memory
		call	NestedProc_RelMem
		invoke GetProcessHeap
		invoke HeapFree,eax,0,ebx
	.elseif eax==WM_SETFOCUS
		mov		eax,[ebx].EDIT.edta.hwnd
		.if eax!=[ebx].EDIT.focus
			mov		eax,[ebx].EDIT.edtb.hwnd
		.endif
		invoke SetFocus,eax
		xor		eax,eax
		jmp		Ex
	.elseif eax==WM_KEYDOWN || eax==WM_CHAR || eax==WM_KEYUP
		invoke SendMessage,[ebx].EDIT.focus,eax,wParam,lParam
		jmp		Ex
	.elseif eax==WM_COMMAND
		mov		eax,wParam
		and		eax,0FFFFh
		.if ax==-2
			invoke IsDlgButtonChecked,hWin,-2
			.if eax
				mov		eax,[ebx].EDIT.nlinenrwt
				mov		[ebx].EDIT.linenrwt,eax
			.else
				mov		[ebx].EDIT.linenrwt,0
			.endif
			invoke SetFocus,[ebx].EDIT.focus
			call	NestedProc_SizeIt
			invoke InvalidateEdit,ebx,[ebx].EDIT.edta.hwnd
			invoke InvalidateEdit,ebx,[ebx].EDIT.edtb.hwnd
		.elseif ax==-3
			mov		ecx,BN_CLICKED
			shl		ecx,16
			or		eax,ecx
			invoke SendMessage,[ebx].EDIT.hpar,WM_COMMAND,eax,[ebx].EDIT.hexp
			invoke SetFocus,[ebx].EDIT.focus
		.elseif ax==-4
			mov		ecx,BN_CLICKED
			shl		ecx,16
			or		eax,ecx
			invoke SendMessage,[ebx].EDIT.hpar,WM_COMMAND,eax,[ebx].EDIT.hcol
			invoke SetFocus,[ebx].EDIT.focus
		.elseif ax==-5
			mov		ecx,[ebx].EDIT.fLock
			xor		ecx,1
			mov		[ebx].EDIT.fLock,ecx
			mov		ecx,BN_CLICKED
			shl		ecx,16
			or		eax,ecx
			invoke SendMessage,[ebx].EDIT.hpar,WM_COMMAND,eax,[ebx].EDIT.hlock
			invoke SetFocus,[ebx].EDIT.focus
		.endif
	.elseif eax==WM_SIZE
		push	edi
		invoke GetWindowLong,hWin,GWL_STYLE
		mov		[ebx].EDIT.fstyle,eax
		invoke GetClientRect,hWin,addr [ebx].EDIT.rc
		mov		eax,[ebx].EDIT.fstyle
		and		eax,STYLE_NOLINENUMBER or STYLE_NOCOLLAPSE or STYLE_NOHSCROLL
		mov		edx,[ebx].EDIT.fstyleex
		and		edx,STYLEEX_LOCK
		.if eax!=STYLE_NOLINENUMBER or STYLE_NOCOLLAPSE or STYLE_NOHSCROLL || edx==STYLEEX_LOCK
			mov		eax,SBWT
			sub		[ebx].EDIT.rc.bottom,eax
		.endif
		call	NestedProc_SizeIt
		xor		edi,edi
		.if !([ebx].EDIT.fstyle&STYLE_NOLINENUMBER)
			invoke MoveWindow,[ebx].EDIT.hlin,0,[ebx].EDIT.rc.bottom,BTNWT,SBWT,TRUE
			add		edi,BTNWT
		.else
			invoke MoveWindow,[ebx].EDIT.hlin,0,0,0,0,TRUE
		.endif
		.if !([ebx].EDIT.fstyle&STYLE_NOCOLLAPSE)
			invoke MoveWindow,[ebx].EDIT.hexp,edi,[ebx].EDIT.rc.bottom,BTNWT,SBWT,TRUE
			add		edi,BTNWT
			invoke MoveWindow,[ebx].EDIT.hcol,edi,[ebx].EDIT.rc.bottom,BTNWT,SBWT,TRUE
			add		edi,BTNWT
		.else
			invoke MoveWindow,[ebx].EDIT.hexp,0,0,0,0,TRUE
			invoke MoveWindow,[ebx].EDIT.hcol,0,0,0,0,TRUE
		.endif
		.if [ebx].EDIT.fstyleex&STYLEEX_LOCK
			invoke MoveWindow,[ebx].EDIT.hlock,edi,[ebx].EDIT.rc.bottom,BTNWT,SBWT,TRUE
			add		edi,BTNWT
		.else
			invoke MoveWindow,[ebx].EDIT.hlock,0,0,0,0,TRUE
		.endif
		mov		eax,[ebx].EDIT.fstyle
		and		eax,STYLE_NOLINENUMBER or STYLE_NOCOLLAPSE or STYLE_NOHSCROLL
		mov		edx,[ebx].EDIT.fstyleex
		and		edx,STYLEEX_LOCK
		.if eax!=STYLE_NOLINENUMBER or STYLE_NOCOLLAPSE or STYLE_NOHSCROLL || edx==STYLEEX_LOCK
			mov		ecx,[ebx].EDIT.rc.right
			sub		ecx,edi
			mov		eax,[ebx].EDIT.fstyle
			and		eax,STYLE_NOSPLITT or STYLE_NOVSCROLL
			.if eax!=STYLE_NOSPLITT or STYLE_NOVSCROLL
				sub		ecx,SBWT
				invoke MoveWindow,[ebx].EDIT.hhscroll,edi,[ebx].EDIT.rc.bottom,ecx,SBWT,TRUE
				.if [ebx].EDIT.fstyle&STYLE_NOSIZEGRIP
					jmp		@f
				.endif
				invoke GetWindowLong,[ebx].EDIT.hpar,GWL_STYLE
				.if eax&WS_MAXIMIZE
					jmp		@f
				.endif
				invoke GetClientRect,[ebx].EDIT.hpar,addr rect
				invoke ClientToScreen,[ebx].EDIT.hpar,addr rect.right
				mov		eax,[ebx].EDIT.rc.bottom
				add		eax,SBWT
				mov		rect.top,eax

				invoke ClientToScreen,hWin,addr rect
				mov		eax,rect.bottom
				sub		eax,rect.top
				.if eax<5
					mov		eax,[ebx].EDIT.rc.right
					sub		eax,SBWT
					invoke MoveWindow,[ebx].EDIT.hgrip,eax,[ebx].EDIT.rc.bottom,SBWT,SBWT,TRUE
					invoke MoveWindow,[ebx].EDIT.hnogrip,0,0,0,0,TRUE
				.else
				  @@:
					mov		eax,[ebx].EDIT.rc.right
					sub		eax,SBWT
					invoke MoveWindow,[ebx].EDIT.hnogrip,eax,[ebx].EDIT.rc.bottom,SBWT,SBWT,TRUE
					invoke MoveWindow,[ebx].EDIT.hgrip,0,0,0,0,TRUE
				.endif
			.else
				invoke MoveWindow,[ebx].EDIT.hhscroll,edi,[ebx].EDIT.rc.bottom,ecx,SBWT,TRUE
				invoke MoveWindow,[ebx].EDIT.hnogrip,0,0,0,0,TRUE
				invoke MoveWindow,[ebx].EDIT.hgrip,0,0,0,0,TRUE
			.endif
		.else
			invoke MoveWindow,[ebx].EDIT.hhscroll,0,0,0,0,TRUE
			invoke MoveWindow,[ebx].EDIT.hgrip,0,0,0,0,TRUE
			invoke MoveWindow,[ebx].EDIT.hnogrip,0,0,0,0,TRUE
		.endif
		invoke GetTopFromYp,ebx,[ebx].EDIT.edta.hwnd,[ebx].EDIT.edta.cpy
		invoke GetTopFromYp,ebx,[ebx].EDIT.edtb.hwnd,[ebx].EDIT.edtb.cpy
		pop		edi
		xor		eax,eax
		jmp		Ex
	.elseif eax==WM_HSCROLL
		push	[ebx].EDIT.cpx
		mov		sinf.cbSize,sizeof sinf
		mov		sinf.fMask,SIF_ALL
		invoke GetScrollInfo,lParam,SB_CTL,addr sinf
		mov		eax,wParam
		and		eax,0FFFFh
		.if eax==SB_THUMBTRACK || eax==SB_THUMBPOSITION
			mov		eax,sinf.nTrackPos
			mov		[ebx].EDIT.cpx,eax
		.elseif eax==SB_LINELEFT
			mov		eax,[ebx].EDIT.fntinfo.fntwt
			.if [ebx].EDIT.cpx>eax
				sub		[ebx].EDIT.cpx,eax
			.else
				mov		[ebx].EDIT.cpx,0
			.endif
		.elseif eax==SB_LINERIGHT
			mov		eax,[ebx].EDIT.fntinfo.fntwt
			add		[ebx].EDIT.cpx,eax
		.elseif eax==SB_PAGELEFT
			mov		eax,sinf.nPage
			.if [ebx].EDIT.cpx > eax
				sub		[ebx].EDIT.cpx,eax
			.else
				mov		[ebx].EDIT.cpx,0
			.endif
		.elseif eax==SB_PAGERIGHT
			mov		eax,sinf.nPage
			add		[ebx].EDIT.cpx,eax
		.endif
		pop		edi
		sub		edi,[ebx].EDIT.cpx
		invoke ScrollEdit,ebx,[ebx].EDIT.edta.hwnd,edi,0
		invoke ScrollEdit,ebx,[ebx].EDIT.edtb.hwnd,edi,0
	.elseif eax==WM_SETFONT
		mov		eax,wParam
		mov		[ebx].EDIT.fnt.hFont,eax
		mov		[ebx].EDIT.fnt.hIFont,eax
		mov		[ebx].EDIT.fnt.hLnrFont,eax
		invoke SetFont,ebx,addr [ebx].EDIT.fnt
	.elseif eax==WM_GETFONT
		mov		eax,[ebx].EDIT.fnt.hFont
		ret
	.elseif eax==WM_STYLECHANGED
		invoke GetWindowLong,hWin,GWL_STYLE
		mov		[ebx].EDIT.fstyle,eax
	.elseif eax==WM_PAINT
		invoke UpdateWindow,[ebx].EDIT.hsta
		invoke UpdateWindow,[ebx].EDIT.edta.hwnd
		invoke UpdateWindow,[ebx].EDIT.edtb.hwnd
		jmp		ExDef
	.elseif eax==REM_RAINIT
		;WM_USER+9999 (=REM_RAINIT) is sendt to a custom control by RadASM (1.2.0.5)
		;to let the custom control fill in default design time values.
		invoke SendMessage,hWin,WM_SETTEXT,0,offset szToolTip
		xor		eax,eax
		jmp		Ex
	.endif
  ExDef:
	invoke DefWindowProc,hWin,uMsg,wParam,lParam
  Ex:
	ret

ErrBeep:
	invoke MessageBeep,MB_ICONHAND
	xor		eax,eax
	ret

NestedProc_SetToolTip:
	mov		ti.cbSize,sizeof TOOLINFO
	mov		ti.uFlags,TTF_IDISHWND or TTF_SUBCLASS
	mov		ti.hWnd,0
	mov		ti.uId,eax
	mov		ti.hInst,0
	mov		ti.lpszText,edx
	invoke SendMessage,[ebx].EDIT.htt,TTM_DELTOOL,NULL,addr ti
	invoke SendMessage,[ebx].EDIT.htt,TTM_ADDTOOL,NULL,addr ti
	retn

NestedProc_SizeIt:
	mov		eax,[ebx].EDIT.fsplitt
	.if eax
		mov		ecx,eax
		mov		eax,[ebx].EDIT.rc.bottom
		mul		ecx
		shr		eax,10
	.endif
	mov		[ebx].EDIT.nsplitt,eax
	.if [ebx].EDIT.nsplitt
		invoke MoveWindow,[ebx].EDIT.edta.hwnd,0,0,[ebx].EDIT.rc.right,[ebx].EDIT.nsplitt,TRUE
		mov		ecx,[ebx].EDIT.nsplitt
		add		ecx,BTNHT
		mov		eax,[ebx].EDIT.rc.bottom
		sub		eax,ecx
		invoke MoveWindow,[ebx].EDIT.edtb.hwnd,0,ecx,[ebx].EDIT.rc.right,eax,TRUE
		invoke MoveWindow,[ebx].EDIT.hsbtn,0,[ebx].EDIT.nsplitt,[ebx].EDIT.rc.right,BTNHT,TRUE
	.else
		invoke MoveWindow,[ebx].EDIT.edta.hwnd,0,0,0,0,TRUE
		mov		ecx,[ebx].EDIT.rc.right
		.if sdword ptr ecx<0
			xor		ecx,ecx
		.endif

		mov		edx,[ebx].EDIT.rc.bottom
		.if sdword ptr edx<0
			xor		edx,edx
		.endif
		invoke MoveWindow,[ebx].EDIT.edtb.hwnd,0,0,ecx,edx,TRUE
		mov		eax,[ebx].EDIT.rc.right
		sub		eax,SBWT
		.if !([ebx].EDIT.fstyle&STYLE_NOSPLITT)
			invoke MoveWindow,[ebx].EDIT.hsbtn,eax,0,SBWT,BTNHT,TRUE
		.else
			invoke MoveWindow,[ebx].EDIT.hsbtn,0,0,0,0,TRUE
		.endif
		.if !([ebx].EDIT.fstyle&STYLE_NOSTATE)
			invoke MoveWindow,[ebx].EDIT.hsta,0,0,4,4,TRUE
		.else
			invoke MoveWindow,[ebx].EDIT.hsta,0,0,0,0,TRUE
		.endif
	.endif
	retn

NestedProc_AllocMem:
	invoke HeapCreate,HEAP_GENERATE_EXCEPTIONS,256*1024,0
	mov		[ebx].EDIT.hHeap,eax
	;Line
	invoke xHeapAlloc,[ebx].EDIT.hHeap,HEAP_GENERATE_EXCEPTIONS or HEAP_ZERO_MEMORY,MAXLINEMEM*8
	mov		[ebx].EDIT.hLine,eax
	mov		[ebx].EDIT.cbLine,MAXLINEMEM*8
	mov		[ebx].EDIT.rpLine,0
	mov		[ebx].EDIT.rpLineFree,sizeof LINE
	;Chars
	invoke xHeapAlloc,[ebx].EDIT.hHeap,HEAP_GENERATE_EXCEPTIONS or HEAP_ZERO_MEMORY,MAXCHARMEM*8
	mov		[ebx].EDIT.hChars,eax
	xor		eax,eax
	mov		[ebx].EDIT.cbChars,MAXCHARMEM*8
	mov		[ebx].EDIT.rpChars,eax
	mov		[ebx].EDIT.rpCharsFree,MAXFREE+sizeof CHARS
	mov		edx,[ebx].EDIT.hLine
	mov		[edx].LINE.rpChars,eax
	mov		edx,[ebx].EDIT.hChars
	mov		[edx].CHARS.max,MAXFREE
	mov		[edx].CHARS.len,eax
	mov		[edx].CHARS.state,eax
	;Undo
	invoke xHeapAlloc,[ebx].EDIT.hHeap,HEAP_GENERATE_EXCEPTIONS or HEAP_ZERO_MEMORY,MAXUNDOMEM
	mov		[ebx].EDIT.hUndo,eax
	mov		[ebx].EDIT.cbUndo,MAXUNDOMEM
	mov		[ebx].EDIT.rpUndo,0
	;Misc
	xor		eax,eax
	mov		[ebx].EDIT.edta.cpy,eax
	mov		[ebx].EDIT.edta.cpxmax,eax
	mov		[ebx].EDIT.edtb.cpy,eax
	mov		[ebx].EDIT.edtb.cpxmax,eax
	mov		[ebx].EDIT.cpx,eax
	mov		[ebx].EDIT.cpMin,eax
	mov		[ebx].EDIT.cpMax,eax
	mov		[ebx].EDIT.blrg.lnMin,eax
	mov		[ebx].EDIT.blrg.clMin,eax
	mov		[ebx].EDIT.blrg.lnMax,eax
	mov		[ebx].EDIT.blrg.clMax,eax
	mov		[ebx].EDIT.fChanged,FALSE
	mov		[ebx].EDIT.cpbrst,-1
	mov		[ebx].EDIT.cpbren,-1
	mov		[ebx].EDIT.cpselbar,-1
	mov		[ebx].EDIT.fLock,FALSE

	retn

NestedProc_RelMem:
	;Free memory
	.if [ebx].EDIT.hHeap
		invoke HeapDestroy,[ebx].EDIT.hHeap
		mov		[ebx].EDIT.hHeap,0
	.endif
	retn

RAWndProc endp

IFDEF DLL
	include RAEditDll.asm
ENDIF

end
