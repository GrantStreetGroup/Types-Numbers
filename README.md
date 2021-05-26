# NAME

Types::Numbers - Type constraints for numbers

# VERSION

version v0.940.1

# DESCRIPTION

Because we deal with numbers every day in our programs and modules, this is an extensive
[Type::Tiny](https://metacpan.org/pod/Type%3A%3ATiny) library of number validations.  Like [Type::Tiny](https://metacpan.org/pod/Type%3A%3ATiny), these types work with
all modern OO platforms and as a standalone type system.

# TYPES

## Overview

All of these types strive for the accurate storage and validation of many different types of
numbers, including some storage types that Perl doesn't natively support.

The hierarchy of the types is as follows:

    (T:S = From Types::Standard)

    Item (T:S)
        Defined (T:S)
            NumLike
                NumRange[`n, `p]
                IntLike
                    SignedInt[`b]
                    UnsignedInt[`b]
                PerlNum
                    PerlSafeInt
                    PerlSafeFloat
                BlessedNum[`d]
                    BlessedInt[`d]
                    BlessedFloat[`d]
                NaN
                Inf[`s]
                FloatSafeNum
                    FloatBinary[`b, `e]
                    FloatDecimal[`d, `e]
                RealNum
                    RealSafeNum
                        FixedBinary[`b, `s]
                        FixedDecimal[`d, `s]

            Value (T:S)
                Str (T:S)
                    Char[`b]

## Basic types

### NumLike

Behaves like `LaxNum` from [Types::Standard](https://metacpan.org/pod/Types%3A%3AStandard), but will also accept blessed number types.  Unlike
`StrictNum`, it will accept `NaN` and `Inf` numbers.

### NumRange\[\`n, \`p\]

Only accepts numbers within a certain range.  The two parameters are the minimums and maximums,
inclusive.

### PerlNum

Exactly like `LaxNum`, but with a different parent.  Only accepts unblessed numbers.

### BlessedNum

Only accepts blessed numbers.  A blessed number would be using something like [Math::BigInt](https://metacpan.org/pod/Math%3A%3ABigInt) or
[Math::BigFloat](https://metacpan.org/pod/Math%3A%3ABigFloat).  It doesn't directly `isa` check those classes, just that the number is
blessed.

### BlessedNum\[\`d\]

A blessed number that supports at least certain amount of digit accuracy.  The blessed number must
support the `accuracy` or `div_scale` method.

For example, `BlessedNum[40]` would work for the default settings of [Math::BigInt](https://metacpan.org/pod/Math%3A%3ABigInt), and supports
numbers at least as big as 128-bit integers.

### NaN

A "not-a-number" value, either embedded into the Perl native float or a blessed `NaN`,
checked via `is_nan`.

### Inf

An infinity value, either embedded into the Perl native float or a blessed `Inf`, checked via
`is_inf`.

### Inf\[\`s\]

    Inf['+']
    Inf['-']

An infinity value with a certain sign, either embedded into the Perl native float or a blessed
`Inf`, checked via `is_inf`.  The parameter must be a plus or minus character.

### RealNum

Like ["NumLike"](#numlike), but does not accept NaN or Inf.  Closer to the spirit of `StrictNum`, but
accepts blessed numbers as well.

## Integers

### IntLike

Behaves like `Int` from [Types::Standard](https://metacpan.org/pod/Types%3A%3AStandard), but will also accept blessed number types and integers
in E notation.  There are no expectations of storage limitations here.  (See ["SignedInt"](#signedint) for
that.)

### PerlSafeInt

A Perl (unblessed) integer number than can safely hold the integer presented.  This varies between
32-bit and 64-bit versions of Perl.

For example, for most 32-bit versions of Perl, the largest integer than can be safely held in a
4-byte NV (floating point number) is `9007199254740992`.  Numbers can go higher than that, but due
to the NV's mantissa length (accuracy), information is lost beyond this point.

In this case, `...992` would pass and `...993` would fail.

(Technically, the max integer is `...993`, but we can't tell the difference between `...993` and
`...994`, so the cut off point is `...992`, inclusive.)

Be aware that Perls compiled with "long doubles" have a unique problem with storage and information
loss: their number form maintains accuracy while their (default) stringified form loses
information.  For example, take the max safe integer for a long double:

    $num = 18446744073709551615;
    say $num;                 # 1.84467440737095516e+19
    say $num == 18446744073709551615;  # true, so the full number is still there
    say sprintf('%u', $num);  # 18446744073709551615

These numbers are considered safe for storage.  If this is not preferred, consider a simple `/e/`
check for stringified E notation.

### BlessedInt

A blessed number than is holding an integer.  (A [Math::BigFloat](https://metacpan.org/pod/Math%3A%3ABigFloat) with an integer value would
still pass.)

### BlessedInt\[\`d\]

A blessed number holding an integer of at most `` `d `` digits (inclusive).  The blessed number
container must also have digit accuracy to support this number.  (See ["BlessedNum\[\`d\]"](#blessednum-d).)

### SignedInt

A signed integer (blessed or otherwise) that can safely hold its own number.  This is different
than ["IntLike"](#intlike), which doesn't check for storage limitations.

### SignedInt\[\`b\]

A signed integer that can hold a `` `b `` bit number and is within those boundaries.  One bit is
reserved for the sign, so the max limit on a 32-bit integer is actually `2**31-1` or
`2147483647`.

### UnsignedInt

Like ["SignedInt"](#signedint), but with a minimum boundary of zero.

### UnsignedInt\[\`b\]

Like ["SignedInt\[\`b\]"](#signedint-b), but for unsigned integers.  Also, unsigned integers gain their extra bit,
so the maximum is twice as high.

## Floating-point numbers

### PerlSafeFloat

A Perl native float that is in the "integer safe" range, or is a NaN/Inf value.

This doesn't guarantee that every single fractional number is going to retain all of its
information here.  It only guarantees that the whole number will be retained, even if the
fractional part is partly or completely lost.

### BlessedFloat

A blessed number that will support fractional numbers.  A [Math::BigFloat](https://metacpan.org/pod/Math%3A%3ABigFloat) number will pass,
whereas a [Math::BigInt](https://metacpan.org/pod/Math%3A%3ABigInt) number will fail.  However, if that [Math::BigInt](https://metacpan.org/pod/Math%3A%3ABigInt) number is capable of
upgrading to a [Math::BigFloat](https://metacpan.org/pod/Math%3A%3ABigFloat), it will pass.

### BlessedFloat\[\`d\]

A float-capable blessed number that supports at least certain amount of digit accuracy.  The number
itself is not boundary checked, as it is excessively difficult to figure out the exact dimensions
of a floating point number.  It would also not be useful for numbers like `0.333333...` to fail
checks.

### FloatSafeNum

A Union of ["PerlSafeFloat"](#perlsafefloat) and ["BlessedFloat"](#blessedfloat).  In other words, a float-capable number with
some basic checks to make sure information is retained.

### FloatBinary\[\`b, \`e\]

A floating-point number that can hold a `` `b `` bit number with `` `e `` bits of exponent, and is within
those boundaries (or is NaN/Inf).  The bit breakdown follows traditional IEEE 754 floating point
standards.  For example:

    FloatBinary[32, 8] =
        32 bits total (`b)
        23 bit  mantissa (significand precision)
         8 bit  exponent (`e)
         1 bit  sign (+/-)

Unlike the `*Int` types, if Perl's native NV cannot support all dimensions of the floating-point
number without losing information, then unblessed numbers are completely off the table.  For
example, assuming a 32-bit machine:

    (UnsignedInt[64])->check( 0 )        # pass
    (UnsignedInt[64])->check( 2 ** 30 )  # pass
    (UnsignedInt[64])->check( 2 ** 60 )  # fail, because 32-bit NVs can't safely hold it

    (FloatBinary[64, 11])->check( 0 )    # fail
    (FloatBinary[64, 11])->check( $any_unblessed_number )  # fail

### FloatDecimal\[\`d, \`e\]

A floating-point number that can hold a `` `d `` digit number with `` `e `` digits of exponent.  Modeled
after the IEEE 754 "decimal" float.  Rejects all Perl NVs that won't support the dimensions.  (See
["FloatBinary\[\`b, \`e\]"](#floatbinary-b-e).)

## Fixed-point numbers

### RealSafeNum

Like ["FloatSafeNum"](#floatsafenum), but rejects any NaN/Inf.

### FixedBinary\[\`b, \`s\]

A fixed-point number, represented as a `` `b `` bit integer than has been shifted by `` `s `` digits.  For example, a
`FixedBinary[32, 4]` has a max of `2**31-1 / 10**4 = 214748.3647`.  Because integers do not hold NaN/Inf, this type fails
on those.

Otherwise, it has the same properties and caveats as the parameterized `Float*` types.

### FixedDecimal\[\`d, \`s\]

Like ["FixedBinary\[\`b, \`s\]"](#fixedbinary-b-s), but for a `` `d `` digit integer.  Or, you could think of `` `d `` and `` `s `` as accuracy (significant
figures) and decimal precision, respectively.

## Characters

Characters are basically encoded numbers, so there's a few types here.  If you need types that handle multi-length strings, you're
better off using [Types::Encodings](https://metacpan.org/pod/Types%3A%3AEncodings).

### Char

A single character.  Unicode is supported, but it must be decoded first.  A multi-byte character that Perl thinks is two separate
characters will fail this type.

### Char\[\`b\]

A single character that fits within `` `b `` bits.  Unicode is supported, but it must be decoded first.

# AUTHOR

Grant Street Group <developers@grantstreet.com>

# COPYRIGHT AND LICENSE

This software is Copyright (c) 2013 - 2021 by Grant Street Group.

This is free software, licensed under:

    The Artistic License 2.0 (GPL Compatible)
