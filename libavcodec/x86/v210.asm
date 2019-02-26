;******************************************************************************
;* V210 SIMD unpack
;* Copyright (c) 2011 Loren Merritt <lorenm@u.washington.edu>
;* Copyright (c) 2011 Kieran Kunhya <kieran@kunhya.com>
;*
;* This file is part of FFmpeg.
;*
;* FFmpeg is free software; you can redistribute it and/or
;* modify it under the terms of the GNU Lesser General Public
;* License as published by the Free Software Foundation; either
;* version 2.1 of the License, or (at your option) any later version.
;*
;* FFmpeg is distributed in the hope that it will be useful,
;* but WITHOUT ANY WARRANTY; without even the implied warranty of
;* MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
;* Lesser General Public License for more details.
;*
;* You should have received a copy of the GNU Lesser General Public
;* License along with FFmpeg; if not, write to the Free Software
;* Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA
;******************************************************************************

%include "libavutil/x86/x86util.asm"

SECTION_RODATA

v210_mult: dw 64,4,64,4,64,4,64,4,64,4,64,4,64,4,64,4
v210_mask: times 8 dd 0x3ff
v210_luma_shuf: db 8,9,0,1,2,3,12,13,4,5,6,7,-1,-1,-1,-1, 8,9,0,1,2,3,12,13,4,5,6,7,-1,-1,-1,-1
v210_chroma_shuf1: db 0,1,8,9,6,7,-1,-1,2,3,4,5,12,13,-1,-1, 0,1,8,9,6,7,-1,-1,2,3,4,5,12,13,-1,-1

; for AVX2 version only
v210_luma_permute: dd 0,1,2,4,5,6,7,7
v210_chroma_permute: dd 0,1,4,5,2,3,6,7
v210_chroma_shuf2: db 0,1,2,3,4,5,8,9,10,11,12,13,-1,-1,-1,-1,0,1,2,3,4,5,8,9,10,11,12,13,-1,-1,-1,-1


SECTION .text

%macro v210_planar_unpack 1

; v210_planar_unpack(const uint32_t *src, uint16_t *y, uint16_t *u, uint16_t *v, int width)
cglobal v210_planar_unpack_%1, 5, 5, 10
    movsxdifnidn r4, r4d
    lea    r1, [r1+2*r4]
    add    r2, r4
    add    r3, r4
    neg    r4

    mova   m3, [v210_luma_shuf]
    mova   m4, [v210_chroma_shuf1]

%if cpuflag(avx2)
    mova   m5, [v210_luma_permute]      ; VPERMD constant must be in a register
    mova   m6, [v210_chroma_permute]    ; VPERMD constant must be in a register
    mova   m7, [v210_chroma_shuf2]
%endif

%if ARCH_X86_64
    mova   m8, [v210_mult]
    mova   m9, [v210_mask]
%endif

.loop:
%ifidn %1, unaligned
    movu   m0, [r0]                    ; yB v5 yA  u5 y9 v4  y8 u4 y7  v3 y6 u3  y5 v2 y4  u2 y3 v1  y2 u1 y1  v0 y0 u0
%else
    mova   m0, [r0]
%endif

%if ARCH_X86_64
    pmullw m1, m0, m8
    psrld  m0, 10                      ; __ v5 __ y9 __ u4 __ y6 __ v2 __ y3 __ u1 __ y0
    pand   m0, m9                      ; 00 v5 00 y9 00 u4 00 y6 00 v2 00 y3 00 u1 00 y0
%else
    pmullw m1, m0, [v210_mult]
    psrld  m0, 10
    pand   m0, [v210_mask]
%endif

    psrlw  m1, 6                       ; yB yA u5 v4 y8 y7 v3 u3 y5 y4 u2 v1 y2 y1 v0 u0
    shufps m2, m1, m0, 0x8d            ; 00 y9 00 y6 yB yA y8 y7 00 y3 00 y0 y5 y4 y2 y1
    pshufb m2, m3                      ; 00 00 yB yA y9 y8 y7 y6 00 00 y5 y4 y3 y2 y1 y0

%if cpuflag(avx2)
    vpermd m2, m5, m2                  ; 00 00 00 00 yB yA y9 y8 y7 y6 y5 y4 y3 y2 y1 y0
%endif

    movu   [r1+2*r4], m2

    shufps m1, m0, 0xd8                ; __ v5 __ u4 u5 v4 v3 u3 __ v2 __ u1 u2 v1 v0 u0
    pshufb m1, m4                      ; 00 v5 v4 v3 00 u5 u4 u3 00 v2 v1 v0 00 u2 u1 u0

%if cpuflag(avx2)
    vpermd m1, m6, m1                  ; 00 v5 v4 v3 00 v2 v1 v0 00 u5 u4 u3 00 u2 u1 u0
    pshufb m1, m7                      ; 00 00 v5 v4 v3 v2 v1 v0 00 00 u5 u4 u3 u2 u1 u0
    movu   [r2+r4], xm1
    vextracti128 [r3+r4], m1, 1
%else
    movq   [r2+r4], m1
    movhps [r3+r4], m1
%endif

    add r0, mmsize                     ; mmsize would be 32 for AVX2
    add r4, 6 + 6*cpuflag(avx2)
    jl  .loop

    REP_RET
%endmacro


INIT_XMM ssse3
v210_planar_unpack aligned

INIT_XMM ssse3
v210_planar_unpack unaligned


%if HAVE_AVX_EXTERNAL
INIT_XMM avx
v210_planar_unpack aligned
%endif

%if HAVE_AVX_EXTERNAL
INIT_XMM avx
v210_planar_unpack unaligned
%endif


%if HAVE_AVX2_EXTERNAL
INIT_YMM avx2
v210_planar_unpack aligned
%endif

%if HAVE_AVX2_EXTERNAL
INIT_YMM avx2
v210_planar_unpack unaligned
%endif
