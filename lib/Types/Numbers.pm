package Types::Numbers;

our $AUTHORITY = 'cpan:GSG';
# ABSTRACT: Type constraints for numbers
# VERSION

#############################################################################
# Modules

use v5.8.8;
use strict;
use warnings;

our @EXPORT_OK = ();

use Type::Library -base;
use Type::Tiny::Intersection;
use Type::Tiny::Union;
use Types::Standard v0.030 ('Bool');  # support for Error::TypeTiny

use Scalar::Util 1.20 (qw(blessed looks_like_number));  # support for overloaded/blessed looks_like_number
use POSIX 'ceil';
use Math::BigInt   1.92;  # somewhat a stab in the dark for a passable version
use Math::BigFloat 1.65;  # earliest version that passes tests
use Data::Float;
use Data::Integer;

use constant {
   _BASE2_LOG => log(2) / log(10),
};

sub _croak ($;@) { require Error::TypeTiny; goto \&Error::TypeTiny::croak }

=encoding utf8

=head1 DESCRIPTION

Because we deal with numbers every day in our programs and modules, this is an extensive
L<Type::Tiny> library of number validations.  Like L<Type::Tiny>, these types work with
all modern OO platforms and as a standalone type system.

=cut

#############################################################################
# Basic globals

my $bigtwo = Math::BigFloat->new(2);
my $bigten = Math::BigFloat->new(10);

# Large 64-bit floats (long doubles) tend to stringify themselves in exponent notation, even
# though the number is still pristine.  IOW, the numeric form is perfect, but the string form
# loses information.  This can be a problem for stringified inlines.
my @df_max_int_parts = Data::Float::float_parts( Data::Float::max_integer );
my $DF_MAX_INT = $bigtwo->copy->bpow($df_max_int_parts[1])->bmul($df_max_int_parts[2])->as_int;

my $SAFE_NUM_MIN = Math::BigInt->new(
    Data::Integer::min_signed_natint   < $DF_MAX_INT * -1 ?
    Data::Integer::min_signed_natint   : $DF_MAX_INT * -1
);
my $SAFE_NUM_MAX = Math::BigInt->new(
    Data::Integer::max_unsigned_natint > $DF_MAX_INT *  1 ?
    Data::Integer::max_unsigned_natint : $DF_MAX_INT *  1,
);

my $meta = __PACKAGE__->meta;

#############################################################################
# Framework types

### TODO: Coercions where safe ###

=head1 TYPES

=head2 Overview

All of these types strive for the accurate storage and validation of many different types of
numbers, including some storage types that Perl doesn't natively support.

The hierarchy of the types is as follows:

    (T:S    = From Types::Standard)
    (~T:C:N = Based on Types::Common::Numeric types)

    Item (T:S)
        Defined (T:S)
            NumLike
                NumRange[`n, `p] (~T:C:N)
                    PositiveNum (~T:C:N)
                    PositiveOrZeroNum (~T:C:N)
                    NegativeNum (~T:C:N)
                    NegativeOrZeroNum (~T:C:N)
                IntLike
                    SignedInt[`b]
                    UnsignedInt[`b]
                    IntRange[`n, `p] (~T:C:N)
                        PositiveInt (~T:C:N)
                        PositiveOrZeroInt (~T:C:N)
                        NegativeInt (~T:C:N)
                        NegativeOrZeroInt (~T:C:N)
                        SingleDigit (~T:C:N)
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

=head2 Basic types

=head3 NumLike

Behaves like C<LaxNum> from L<Types::Standard>, but will also accept blessed number types.  Unlike
C<StrictNum>, it will accept C<NaN> and C<Inf> numbers.

=cut

# Moose and Type::Tiny types both don't seem to support Math::Big* = Num.
# So, we have to start almost from stratch.
my $_NumLike = $meta->add_type(
    name       => 'NumLike',
    parent     => Types::Standard::Defined,
    library    => __PACKAGE__,
    constraint => sub { looks_like_number $_ },
    inlined    => sub { "Scalar::Util::looks_like_number($_[1])" },
);

=head3 NumRange[`n, `p]

Only accepts numbers within a certain range.  By default, the two parameters are the minimums and maximums,
inclusive.  However, this type is also compatible with a few different parameter styles, a la L<Types::Common::Numeric>.

The minimum/maximums can be omitted or undefined.  Or two extra boolean parameters can be added to specify exclusivity:

    NumRange[0.1, 10.0, 0, 0]  # both inclusive
    NumRange[0.1, 10.0, 0, 1]  # exclusive maximum, so 10.0 is invalid
    NumRange[0.1, 10.0, 1, 0]  # exclusive minimum, so 0.1 is invalid
    NumRange[0.1, 10.0, 1, 1]  # both exclusive

    NumRange[0.1]                # lower bound check only
    NumRange[undef, 10.0]        # upper bound check only
    NumRange[0.1, undef, 1]      # lower bound check only, exclusively
    NumRange[undef, 10.0, 1, 1]  # upper bound check only, exclusively (third param ignored)

=cut

my $_NumRange = $meta->add_type(
    name       => 'NumRange',
    parent     => $_NumLike,
    library    => __PACKAGE__,
    # kinda pointless without the parameters
    constraint_generator => sub {
        my $self = $Type::Tiny::parameterize_type;
        my ($min, $max, $min_excl, $max_excl) = @_;
        !defined $min      or looks_like_number($min) or _croak( "First parameter to NumRange[`n, `p] expected to be a number; got $min");
        !defined $max      or looks_like_number($max) or _croak("Second parameter to NumRange[`n, `p] expected to be a number; got $max");
        !defined $min_excl or Bool->check($min_excl)  or _croak( "Third parameter to NumRange[`n, `p] expected to be a boolean; got $min_excl");
        !defined $max_excl or Bool->check($max_excl)  or _croak("Fourth parameter to NumRange[`n, `p] expected to be a boolean; got $max_excl");

        $min_excl = 0 unless defined $min_excl;
        $max_excl = 0 unless defined $max_excl;

        my ($Imin, $Imax) = ($min, $max);
        $Imin = blessed($min)."\->new('$min')" if defined $min && blessed $min;
        $Imax = blessed($max)."\->new('$max')" if defined $max && blessed $max;

        my $display_name = 'NumRange['.
            join(', ', map { defined $_ ? $_ : 'undef' } ($min, $max, $min_excl, $max_excl) ).
        ']';

        Type::Tiny->new(
            display_name => $display_name,
            parent       => $self,
            library      => __PACKAGE__,
            constraint   => sub {
                my $val = $_;

                # AND checks, so return false on the logically-opposite checks (>= --> <)
                if (defined $min) {
                    return !!0 if $val <  $min;
                    return !!0 if $val == $min && $min_excl;
                }
                if (defined $max) {
                    return !!0 if $val >  $max;
                    return !!0 if $val == $max && $max_excl;
                }

                # NaN still passes both NumLike and the anti-checks above, so we use this seemingly-paradoxical
                # logical check here to reject it
                return $val == $val;
            },
            inlined    => sub {
                my ($self, $val) = @_;
                my @checks = (undef);  # parent check
                push @checks, join(' ', $val, ($min_excl ? '>' : '>='), $Imin) if defined $min;
                push @checks, join(' ', $val, ($max_excl ? '<' : '<='), $Imax) if defined $max;
                @checks;
            },
        );
    },
);

# we need to optimize out all of the NumLike checks
my $_NumRange_perlsafe = Type::Tiny->new(
    display_name => "_NumRange_perlsafe",
    parent     => $_NumLike,
    # no equals because MAX+1 = MAX after truncation
    constraint => sub { $_ > $SAFE_NUM_MIN && $_ < $SAFE_NUM_MAX },
    inlined    => sub { "$_ > ".$SAFE_NUM_MIN, "$_ < ".$SAFE_NUM_MAX },
);

=head3 PerlNum

Exactly like C<LaxNum>, but with a different parent.  Only accepts unblessed numbers.

=cut

my $_PerlNum = $meta->add_type(
    name       => 'PerlNum',
    parent     => $_NumLike,
    library    => __PACKAGE__,

    # LaxNum has parental constraints that matter, so we can't just blindly steal its own
    # constraint by itself.  The inlined sub, OTOH, is self-sufficient.
    constraint => sub { Types::Standard::LaxNum->check($_) },
    inlined    => Types::Standard::LaxNum->inlined,
);

=head3 BlessedNum

Only accepts blessed numbers.  A blessed number would be using something like L<Math::BigInt> or
L<Math::BigFloat>.  It doesn't directly C<isa> check those classes, just that the number is
blessed.

=head3 BlessedNum[`d]

A blessed number that supports at least certain amount of digit accuracy.  The blessed number must
support the C<accuracy> or C<div_scale> method.

For example, C<BlessedNum[40]> would work for the default settings of L<Math::BigInt>, and supports
numbers at least as big as 128-bit integers.

=cut

my $_BlessedNum = $meta->add_type( Type::Tiny::Intersection->new(
    name         => 'BlessedNum',
    display_name => 'BlessedNum',
    library      => __PACKAGE__,
    type_constraints => [ $_NumLike, Types::Standard::Object ],
    constraint_generator => sub {
        my $self = $Type::Tiny::parameterize_type;
        my $digits = shift;
        $digits =~ /\A[0-9]+\z/ or _croak("Parameter to BlessedNum[`d] expected to be a positive integer; got $digits");

        Type::Tiny->new(
            display_name => "BlessedNum[$digits]",
            parent     => $self,
            library    => __PACKAGE__,
            constraint => sub {
                my $val = $_;

                $val->can('accuracy')  && $val->accuracy  && $val->accuracy  >= $digits ||
                $val->can('div_scale') && $val->div_scale && $val->div_scale >= $digits;
            },
            inlined    => sub {
                my ($self, $val) = @_;

                return (undef,
                    "$val->can('accuracy')  && $val->accuracy  && $val->accuracy  >= $digits || ".
                    "$val->can('div_scale') && $val->div_scale && $val->div_scale >= $digits"
                );
            },
        );
    },
) );

=head3 NaN

A "not-a-number" value, either embedded into the Perl native float or a blessed C<NaN>,
checked via C<is_nan>.

=cut

my $_NaN = $meta->add_type(
    name       => 'NaN',
    parent     => $_NumLike,
    library    => __PACKAGE__,
    constraint => sub {
        my $val = $_;

        Types::Standard::Object->check($val) && $val->can('is_nan') && $val->is_nan ||
        Data::Float::float_is_nan($val);
    },
    inlined    => sub {
        my ($self, $val) = @_;
        return (undef,
            Types::Standard::Object->inline_check($val)." && $val->can('is_nan') && $val->is_nan ||".
            "Data::Float::float_is_nan($val)"
        );
    },
);

=head3 Inf

An infinity value, either embedded into the Perl native float or a blessed C<Inf>, checked via
C<is_inf>.

=head3 Inf[`s]

   Inf['+']
   Inf['-']

An infinity value with a certain sign, either embedded into the Perl native float or a blessed
C<Inf>, checked via C<is_inf>.  The parameter must be a plus or minus character.

=cut

my $_Inf = $meta->add_type(
    name       => 'Inf',
    parent     => $_NumLike,
    library    => __PACKAGE__,
    constraint => sub {
        my $val = $_;

        Types::Standard::Object->check($val) && $val->can('is_inf') && ($val->is_inf('+') || $val->is_inf('-')) ||
        Data::Float::float_is_infinite($val);
    },
    inlined    => sub {
        my ($self, $val) = @_;
        return (undef,
            Types::Standard::Object->inline_check($val)." && $val->can('is_inf') && ($val->is_inf('+') || $val->is_inf('-')) ||".
            "Data::Float::float_is_infinite($val)"
        );
    },
    constraint_generator => sub {
        my $self = $Type::Tiny::parameterize_type;
        my $sign = shift;
        $sign =~ /\A[+\-]\z/ or _croak("Parameter to Inf[`s] expected to be a plus or minus sign; got $sign");

        Type::Tiny->new(
            display_name => "Inf[$sign]",
            parent     => $self,
            library    => __PACKAGE__,
            constraint => sub {
                my $val = $_;

                Types::Standard::Object->check($val) && $val->can('is_inf') && $val->is_inf($sign) ||
                Data::Float::float_is_infinite($val) && Data::Float::float_sign($val) eq $sign;
            },
            inlined    => sub {
                my ($self, $val) = @_;

                return (undef,
                   Types::Standard::Object->inline_check($val)." && $val->can('is_inf') && $val->is_inf('$sign') || ".
                   "Data::Float::float_is_infinite($val) && Data::Float::float_sign($val) eq '$sign'"
                );
            },
        );
    },
);

# this is used a lot for floats, but we need to optimize out all of the NumLike checks
my $_NaNInf = Type::Tiny::Union->new(
    type_constraints => [ $_NaN, $_Inf ],
)->create_child_type(
    name       => 'NaNInf',
    constraint => sub {
        # looks_like_number($_) &&
        Types::Standard::Object->check($_) && (
            $_->can('is_nan') && $_->is_nan ||
            $_->can('is_inf') && ($_->is_inf('+') || $_->is_inf('-'))
        ) || Data::Float::float_is_nan($_) || Data::Float::float_is_infinite($_)
    },
    inlined    => sub {
        my ($self, $val) = @_;
        # looks_like_number($val) &&
        Types::Standard::Object->inline_check($val)." && ( ".  # NOTE: A && (B) || C || D, so don't list-separate
            "$val->can('is_nan') && $val->is_nan || ".
            "$val->can('is_inf') && ($val->is_inf('+') || $val->is_inf('-')) ".
        ") || Data::Float::float_is_nan($val) || Data::Float::float_is_infinite($val)";
    },
);

my $_not_NaNInf = $_NaNInf->complementary_type;

=head3 RealNum

Like L</NumLike>, but does not accept NaN or Inf.  Closer to the spirit of C<StrictNum>, but
accepts blessed numbers as well.

=cut

my $_RealNum = $meta->add_type( Type::Tiny::Intersection->new(
    name         => 'RealNum',
    display_name => 'RealNum',
    library      => __PACKAGE__,
    type_constraints => [ $_NumLike, $_not_NaNInf ],
) );

#############################################################################
# Integer types

=head2 Integers

=cut

# Helper subs
sub __integer_bits_vars {
    my ($bits, $is_unsigned) = @_;

    my $sbits = $bits - 1;

    my ($neg, $spos, $upos) = (
        $bigtwo->copy->bpow($sbits)->bmul(-1),
        $bigtwo->copy->bpow($sbits)->bsub(1),
        $bigtwo->copy->bpow( $bits)->bsub(1),
    );
    my $sdigits = ceil( $sbits * _BASE2_LOG );
    my $udigits = ceil(  $bits * _BASE2_LOG );

    return $is_unsigned ?
        (0,    $upos, $udigits) :
        ($neg, $spos, $sdigits)
    ;
}

=head3 IntLike

Behaves like C<Int> from L<Types::Standard>, but will also accept blessed number types and integers
in E notation.  There are no expectations of storage limitations here.  (See L</SignedInt> for
that.)

=cut

### XXX: This string equality check is necessary because Math::BigInt seems to think 1.5 == 1.
### However, this is problematic with long doubles that stringify into E notation.
my $_IntLike = $meta->add_type(
    name       => 'IntLike',
    parent     => $_NumLike,
    library    => __PACKAGE__,
    constraint => sub { /\d+/ && int($_) == $_ && (int($_) eq $_ || !ref($_)) },
    inlined    => sub {
        my ($self, $val) = @_;
        (undef, "$val =~ /\\d+/", "int($val) == $val", "(int($val) eq $val || !ref($val))");
    },
);

=head3 IntRange[`n, `p]

Only accepts integers within a certain range.  By default, the two parameters are the minimums and maximums,
inclusive.  Though, the minimum/maximums can be omitted or undefined.

=cut

my $_IntRange = $meta->add_type(
    name       => 'IntRange',
    parent     => $_IntLike,
    library    => __PACKAGE__,
    # kinda pointless without the parameters
    constraint_generator => sub {
        my $self = $Type::Tiny::parameterize_type;
        my ($min, $max) = @_;
        !defined $min or looks_like_number($min) or _croak( "First parameter to IntRange[`n, `p] expected to be a number; got $min");
        !defined $max or looks_like_number($max) or _croak("Second parameter to IntRange[`n, `p] expected to be a number; got $max");

        my ($Imin, $Imax) = ($min, $max);
        $Imin = blessed($min)."\->new('$min')" if defined $min && blessed $min;
        $Imax = blessed($max)."\->new('$max')" if defined $max && blessed $max;

        my $display_name = 'IntRange['.
            join(', ', map { defined $_ ? $_ : 'undef' } ($min, $max) ).
        ']';

        Type::Tiny->new(
            display_name => $display_name,
            parent       => $self,
            library      => __PACKAGE__,
            constraint   => sub {
                my $val = $_;

                # AND checks, so return false on the logically-opposite checks (>= --> <)
                return !!0 if defined $min && $val < $min;
                return !!0 if defined $max && $val > $max;
                return !!1;
            },
            inlined    => sub {
                my ($self, $val) = @_;
                my @checks = (undef);  # parent check
                push @checks, "$val >= $Imin" if defined $min;
                push @checks, "$val <= $Imax" if defined $max;
                @checks;
            },
        );
    },
);

=head3 PerlSafeInt

A Perl (unblessed) integer number than can safely hold the integer presented.  This varies between
32-bit and 64-bit versions of Perl.

For example, for most 32-bit versions of Perl, the largest integer than can be safely held in a
4-byte NV (floating point number) is C<9007199254740992>.  Numbers can go higher than that, but due
to the NV's mantissa length (accuracy), information is lost beyond this point.

In this case, C<...992> would pass and C<...993> would fail.

(Technically, the max integer is C<...993>, but we can't tell the difference between C<...993> and
C<...994>, so the cut off point is C<...992>, inclusive.)

Be aware that Perls compiled with "long doubles" have a unique problem with storage and information
loss: their number form maintains accuracy while their (default) stringified form loses
information.  For example, take the max safe integer for a long double:

    $num = 18446744073709551615;
    say $num;                 # 1.84467440737095516e+19
    say $num == 18446744073709551615;  # true, so the full number is still there
    say sprintf('%u', $num);  # 18446744073709551615

These numbers are considered safe for storage.  If this is not preferred, consider a simple C</e/>
check for stringified E notation.

=cut

my $_PerlSafeInt = $meta->add_type( Type::Tiny::Intersection->new(
    library    => __PACKAGE__,
    type_constraints => [ $_PerlNum, $_IntLike, $_NumRange_perlsafe ],
)->create_child_type(
    name       => 'PerlSafeInt',
    library    => __PACKAGE__,
    inlined    => sub {
        my $val = $_[1];
        ("defined $val", "!ref($val)", "$val =~ /\\d+/", "int($val) == $val", $_NumRange_perlsafe->inline_check($val));
    },
) );

=head3 BlessedInt

A blessed number than is holding an integer.  (A L<Math::BigFloat> with an integer value would
still pass.)

=head3 BlessedInt[`d]

A blessed number holding an integer of at most C<`d> digits (inclusive).  The blessed number
container must also have digit accuracy to support this number.  (See L</BlessedNum[`d]>.)

=cut

my $_BlessedInt = $meta->add_type( Type::Tiny::Intersection->new(
    library    => __PACKAGE__,
    type_constraints => [ $_BlessedNum, $_IntLike ],
)->create_child_type(
    name       => 'BlessedInt',
    library    => __PACKAGE__,
    inlined    => sub {
        my $val = $_[1];
        Types::Standard::Object->inline_check($val), "$val =~ /\\d+/", "int($val) == $val", "int($val) eq $val";
    },
    constraint_generator => sub {
        my $self = $Type::Tiny::parameterize_type;
        my $digits = shift;
        $digits =~ /\A[0-9]+\z/ or _croak("Parameter to BlessedInt[`d] expected to be a positive integer; got $digits");

        my $_BlessedNum_param = $_BlessedNum->parameterize($digits);

        Type::Tiny->new(
            display_name => "BlessedInt[$digits]",
            parent     => $self,
            library    => __PACKAGE__,
            constraint => sub {
                $_IntLike->check($_) && $_BlessedNum_param->check($_) && do {
                    my $num = $_;
                    $num =~ s/\D+//g;
                    length($num) <= $digits
                }
            },
            inlined    => sub {
                my $val = $_[1];
                return (
                    $_BlessedNum_param->inline_check($val),
                    "$val =~ /\\d+/", "int($val) == $val", "int($val) eq $val",
                    "do { ".
                        'my $num = '.$val.'; '.
                        '$num =~ s/\D+//g; '.
                        'length($num) <= '.$digits.' '.
                    '}'
                );
            },
        );
    },
) );

=head3 SignedInt

A signed integer (blessed or otherwise) that can safely hold its own number.  This is different
than L</IntLike>, which doesn't check for storage limitations.

=head3 SignedInt[`b]

A signed integer that can hold a C<`b> bit number and is within those boundaries.  One bit is
reserved for the sign, so the max limit on a 32-bit integer is actually C<2**31-1> or
C<2147483647>.

=cut

$meta->add_type( Type::Tiny::Union->new(
    #parent     => $_IntLike,
    library    => __PACKAGE__,
    type_constraints => [ $_PerlSafeInt, $_BlessedInt ],
)->create_child_type(
    name       => 'SignedInt',
    library    => __PACKAGE__,
    inlined    => sub {
        my $val = $_[1];
        return (
            $_IntLike->inline_check($val),
            $_NumRange_perlsafe->inline_check($val).' || '.Types::Standard::Object->inline_check($val)
        );
    },
    constraint_generator => sub {
        my $self = $Type::Tiny::parameterize_type;
        my $bits = shift;
        $bits =~ /\A[0-9]+\z/ or _croak("Parameter to SignedInt[`b] expected to be a positive integer; got $bits");

        my ($min, $max, $digits) = __integer_bits_vars($bits, 0);
        my $_BlessedInt_param = $_BlessedInt->parameterize($digits);
        my $_NumRange_param   = $_NumRange  ->parameterize($min, $max);

        Type::Tiny::Intersection->new(
            library    => __PACKAGE__,
            type_constraints => [ $self, ($_PerlSafeInt|$_BlessedInt_param), $_NumRange_param ],
        )->create_child_type(
            display_name => "SignedInt[$bits]",
            inlined    => sub {
                my $val = $_[1];
                return (
                    $_PerlSafeInt->inline_check($val).' || '.$_BlessedInt_param->inline_check($val),
                    $_NumRange_param->inline_check($val)
                );
            },
        );
    },
) );

=head3 UnsignedInt

Like L</SignedInt>, but with a minimum boundary of zero.

=head3 UnsignedInt[`b]

Like L</SignedInt[`b]>, but for unsigned integers.  Also, unsigned integers gain their extra bit,
so the maximum is twice as high.

=cut

$meta->add_type(
    name       => 'UnsignedInt',
    parent     => $_IntLike,
    library    => __PACKAGE__,
    constraint => sub { $_IntLike->check($_) && $_ >= 0 && ($_PerlSafeInt->check($_) || $_BlessedNum->check($_)) },
    inlined    => sub {
        my $val = $_[1];
        (undef, "$val >= 0", '('.
            $_NumRange_perlsafe->inline_check($val).' || '.Types::Standard::Object->inline_check($val).
        ')');
    },
    constraint_generator => sub {
        my $self = $Type::Tiny::parameterize_type;
        my $bits = shift;
        $bits =~ /\A[0-9]+\z/ or _croak("Parameter to UnsignedInt[`b] expected to be a positive integer; got $bits");

        my ($min, $max, $digits) = __integer_bits_vars($bits, 1);
        my $_BlessedNum_param = $_BlessedNum->parameterize($digits);  # IntLike check extracted out
        my $_NumRange_param   = $_NumRange  ->parameterize($min, $max);

        # inline will already have the IntLike check, and maybe not need the extra NumRange check
        my $perlsafe_inline = $min >= $SAFE_NUM_MIN && $max <= $SAFE_NUM_MAX ?
            sub { Types::Standard::Str->inline_check($_[0]) } :
            sub { '('.Types::Standard::Str->inline_check($_[0]).' && '.$_NumRange_perlsafe->inline_check($_[0]).')' }
        ;

        Type::Tiny->new(
            display_name => "UnsignedInt[$bits]",
            parent     => $self,
            library    => __PACKAGE__,
            constraint => sub {
                $_IntLike->check($_) && $_NumRange_param->check($_) &&
                ($_PerlSafeInt->check($_) || $_BlessedNum_param->check($_));
            },
            inlined    => sub {
                my $val = $_[1];
                return (
                    $_IntLike->inline_check($val),
                    $_NumRange_param->inline_check($val),
                    $perlsafe_inline->($val).' || '.$_BlessedNum_param->inline_check($val)
                );
            },
        );
    },
);

#############################################################################
# Float/fixed types

=head2 Floating-point numbers

=head3 PerlSafeFloat

A Perl native float that is in the "integer safe" range, or is a NaN/Inf value.

This doesn't guarantee that every single fractional number is going to retain all of its
information here.  It only guarantees that the whole number will be retained, even if the
fractional part is partly or completely lost.

=cut

my $_PerlSafeFloat = $meta->add_type(
    name       => 'PerlSafeFloat',
    parent     => $_PerlNum,
    library    => __PACKAGE__,
    constraint => sub { $_NumRange_perlsafe->check($_) || Data::Float::float_is_nan($_) || Data::Float::float_is_infinite($_) },
    inlined    => sub {
        my ($self, $val) = @_;
        return (undef,
            $_NumRange_perlsafe->inline_check($val)." || Data::Float::float_is_nan($val) || Data::Float::float_is_infinite($val)"
        );
    },
);

=head3 BlessedFloat

A blessed number that will support fractional numbers.  A L<Math::BigFloat> number will pass,
whereas a L<Math::BigInt> number will fail.  However, if that L<Math::BigInt> number is capable of
upgrading to a L<Math::BigFloat>, it will pass.

=head3 BlessedFloat[`d]

A float-capable blessed number that supports at least certain amount of digit accuracy.  The number
itself is not boundary checked, as it is excessively difficult to figure out the exact dimensions
of a floating point number.  It would also not be useful for numbers like C<0.333333...> to fail
checks.

=cut

my $_BlessedFloat = $meta->add_type(
    name       => 'BlessedFloat',
    parent     => $_BlessedNum,
    library    => __PACKAGE__,
    constraint => sub { blessed($_)->new(1.2) == 1.2 },
    inlined    => sub {
        my ($self, $val) = @_;
        undef, "Scalar::Util::blessed($val)\->new(1.2) == 1.2";
    },
    constraint_generator => sub {
        my $self = $Type::Tiny::parameterize_type;
        my $digits = shift;
        $digits =~ /\A[0-9]+\z/ or _croak("Parameter to BlessedFloat[`d] expected to be a positive integer; got $digits");

        my $_BlessedNum_param = $_BlessedNum->parameterize($digits);

        Type::Tiny->new(
            display_name => "BlessedFloat[$digits]",
            parent     => $self,
            library    => __PACKAGE__,
            constraint => sub { $_BlessedNum_param->check($_) && blessed($_)->new(1.2) == 1.2 },
            inlined    => sub {
                my ($self, $val) = @_;
                ($_BlessedNum_param->inline_check($val), "Scalar::Util::blessed($val)\->new(1.2) == 1.2");
            },
        );
    },
);

=head3 FloatSafeNum

A Union of L</PerlSafeFloat> and L</BlessedFloat>.  In other words, a float-capable number with
some basic checks to make sure information is retained.

=cut

my $_FloatSafeNum = $meta->add_type( Type::Tiny::Union->new(
    library    => __PACKAGE__,
    type_constraints => [ $_PerlSafeFloat, $_BlessedFloat ],
)->create_child_type(
    name       => 'FloatSafeNum',
    library    => __PACKAGE__,
    inlined    => sub {
        my ($self, $val) = @_;
        return (
            undef,
            "!ref($val)",
            "Scalar::Util::blessed($val)->new(1.2) == 1.2",
            '('.
                $_NumRange_perlsafe->inline_check($val)." || Data::Float::float_is_nan($val) || Data::Float::float_is_infinite($val)".
            ') || '.Types::Standard::Object->inline_check($val),
        );
    },
) );

=head3 FloatBinary[`b, `e]

A floating-point number that can hold a C<`b> bit number with C<`e> bits of exponent, and is within
those boundaries (or is NaN/Inf).  The bit breakdown follows traditional IEEE 754 floating point
standards.  For example:

    FloatBinary[32, 8] =
        32 bits total (`b)
        23 bit  mantissa (significand precision)
         8 bit  exponent (`e)
         1 bit  sign (+/-)

Unlike the C<*Int> types, if Perl's native NV cannot support all dimensions of the floating-point
number without losing information, then unblessed numbers are completely off the table.  For
example, assuming a 32-bit machine:

   (UnsignedInt[64])->check( 0 )        # pass
   (UnsignedInt[64])->check( 2 ** 30 )  # pass
   (UnsignedInt[64])->check( 2 ** 60 )  # fail, because 32-bit NVs can't safely hold it

   (FloatBinary[64, 11])->check( 0 )    # fail
   (FloatBinary[64, 11])->check( $any_unblessed_number )  # fail

=cut

### NOTE: These two are very close to another type, but there's just too many variables
### to throw into a typical type

sub __real_constraint_generator {
    my ($is_perl_safe, $digits, $_NumRange_param, $no_naninf) = @_;
    my $_BlessedFloat_param = $_BlessedFloat->parameterize($digits);

    if ($no_naninf) {
        return $is_perl_safe ?
           sub { ( $_PerlNum->check($_) || $_BlessedFloat_param->check($_) ) && $_NumRange_param->check($_) } :
           sub { $_BlessedFloat_param->check($_) && $_NumRange_param->check($_) }
        ;
    }
    else {
        return $is_perl_safe ?
           sub { ( $_PerlNum->check($_) || $_BlessedFloat_param->check($_) ) && $_NumRange_param->check($_) || $_NaNInf->check($_) } :
           sub { $_BlessedFloat_param->check($_) && ( $_NumRange_param->check($_) || $_NaNInf->check($_) ); }
        ;
    }
}

sub __real_inline_generator {
    my ($is_perl_safe, $digits, $_NumRange_param, $no_naninf) = @_;
    my $_BlessedFloat_param = $_BlessedFloat->parameterize($digits);

    if ($no_naninf) {
        return $is_perl_safe ?
            sub { (
                $_PerlNum->inline_check($_[1]).' || '.$_BlessedFloat_param->inline_check($_[1]),
                $_NumRange_param->inline_check($_[1])
            ) } :
            sub { ($_BlessedFloat_param->inline_check($_[1]), $_NumRange_param->inline_check($_[1])) }
        ;
    }
    else {
        return $is_perl_safe ?
            sub { (
                $_PerlNum->inline_check($_[1]).' || '.$_BlessedFloat_param->inline_check($_[1]),
                $_NumRange_param->inline_check($_[1]).' || '.$_NaNInf->inline_check($_[1])
            ) } :
            sub { (
                $_BlessedFloat_param->inline_check($_[1]),
                $_NumRange_param->inline_check($_[1]).' || '.$_NaNInf->inline_check($_[1])
            ) }
        ;
    }
}

$meta->add_type(
    name       => 'FloatBinary',
    parent     => $_FloatSafeNum,
    library    => __PACKAGE__,
    # kinda pointless without the parameters
    constraint_generator => sub {
        my $self = $Type::Tiny::parameterize_type;
        my ($bits, $ebits) = (shift, shift);
        $bits  =~ /\A[0-9]+\z/ or _croak( "First parameter to FloatBinary[`b, `e] expected to be a positive integer; got $bits");
        $ebits =~ /\A[0-9]+\z/ or _croak("Second parameter to FloatBinary[`b, `e] expected to be a positive integer; got $ebits");

        my $sbits = $bits - 1 - $ebits;  # remove sign bit and exponent bits = significand precision

        # MAX = (2 - 2**(-$sbits-1)) * 2**($ebits-1)
        my $emax = $bigtwo->copy->bpow($ebits-1)->bsub(1);             # Y = (2**($ebits-1)-1)
        my $smin = $bigtwo->copy->bpow(-$sbits-1)->bmul(-1)->badd(2);  # Z = (2 - X) = -X + 2  (where X = 2**(-$sbits-1) )
        my $max  = $bigtwo->copy->bpow($emax)->bmul($smin);            # MAX = 2**Y * Z

        my $digits = ceil( $sbits * _BASE2_LOG );

        my $is_perl_safe = (
            Data::Float::significand_bits >= $sbits &&
            Data::Float::max_finite_exp   >= 2 ** $ebits - 1 &&
            Data::Float::have_infinite &&
            Data::Float::have_nan
        );

        my $_NumRange_param = $_NumRange->parameterize(-$max, $max);

        Type::Tiny->new(
            display_name => "FloatBinary[$bits, $ebits]",
            parent     => $self,
            library    => __PACKAGE__,
            constraint => __real_constraint_generator($is_perl_safe, $digits, $_NumRange_param),
            inlined    => __real_inline_generator    ($is_perl_safe, $digits, $_NumRange_param),
        );
    },
);

=head3 FloatDecimal[`d, `e]

A floating-point number that can hold a C<`d> digit number with C<`e> digits of exponent.  Modeled
after the IEEE 754 "decimal" float.  Rejects all Perl NVs that won't support the dimensions.  (See
L</FloatBinary[`b, `e]>.)

=cut

$meta->add_type(
    name       => 'FloatDecimal',
    parent     => $_FloatSafeNum,
    library    => __PACKAGE__,
    # kinda pointless without the parameters
    constraint_generator => sub {
        my $self = $Type::Tiny::parameterize_type;
        my ($digits, $emax) = (shift, shift);
        $digits =~ /\A[0-9]+\z/ or _croak( "First parameter to FloatDecimal[`d, `e] expected to be a positive integer; got $digits");
        $emax   =~ /\A[0-9]+\z/ or _croak("Second parameter to FloatDecimal[`d, `e] expected to be a positive integer; got $emax");

        # We're not going to worry about the (extreme) edge case that
        # Perl might be compiled with decimal float NVs, but we still
        # need to convert to base-2.
        my $sbits = ceil( $digits / _BASE2_LOG );
        my $emax2 = ceil( $emax   / _BASE2_LOG );

        my $max = $bigten->copy->bpow($emax)->bmul( '9.'.('9' x ($digits-1)) );

        my $is_perl_safe = (
            Data::Float::significand_bits >= $sbits &&
            Data::Float::max_finite_exp   >= $emax2 &&
            Data::Float::have_infinite &&
            Data::Float::have_nan
        );

        my $_NumRange_param = $_NumRange->parameterize(-$max, $max);

        Type::Tiny->new(
            display_name => "FloatDecimal[$digits, $emax]",
            parent     => $self,
            library    => __PACKAGE__,
            constraint => __real_constraint_generator($is_perl_safe, $digits, $_NumRange_param),
            inlined    => __real_inline_generator    ($is_perl_safe, $digits, $_NumRange_param),
        );
    },
);

=head2 Fixed-point numbers

=head3 RealSafeNum

Like L</FloatSafeNum>, but rejects any NaN/Inf.

=cut

my $_RealSafeNum = $meta->add_type( Type::Tiny::Intersection->new(
    library    => __PACKAGE__,
    type_constraints => [ $_RealNum, $_FloatSafeNum ],
)->create_child_type(
    name       => 'RealSafeNum',
    library    => __PACKAGE__,
    inlined    => sub {
        my ($self, $val) = @_;
        return (
            $_NumLike->inline_check($val),
            "( !ref($val) && ".$_NumRange_perlsafe->inline_check($val)." && not (".
                "Data::Float::float_is_nan($val) || Data::Float::float_is_infinite($val))".
            ') || ('.
                Types::Standard::Object->inline_check($val)." && Scalar::Util::blessed($val)->new(1.2) == 1.2 && ".
                "not ($val->can('is_nan') && $val->is_nan || $val->can('is_inf') && ($val->is_inf('+') || $val->is_inf('-')) )".
            ')'
        );
    },
) );

=head3 FixedBinary[`b, `s]

A fixed-point number, represented as a C<`b> bit integer than has been shifted by C<`s> digits.  For example, a
C<FixedBinary[32, 4]> has a max of C<2**31-1 / 10**4 = 214748.3647>.  Because integers do not hold NaN/Inf, this type fails
on those.

Otherwise, it has the same properties and caveats as the parameterized C<Float*> types.

=cut

$meta->add_type(
    name       => 'FixedBinary',
    parent     => $_RealSafeNum,
    library    => __PACKAGE__,
    # kinda pointless without the parameters
    constraint_generator => sub {
        my $self = $Type::Tiny::parameterize_type;
        my ($bits, $scale) = (shift, shift);
        $bits  =~ /\A[0-9]+\z/ or _croak( "First parameter to FixedBinary[`b, `s] expected to be a positive integer; got $bits");
        $scale =~ /\A[0-9]+\z/ or _croak("Second parameter to FixedBinary[`b, `s] expected to be a positive integer; got $scale");

        my $sbits = $bits - 1;

        # So, we have a base-10 scale and a base-2 set of $bits.  Lovely.
        # We can't actually figure out if it's Perl safe until we find the
        # $max, adjust with the $scale, and then go BACK to base-2 limits.
        my $div = $bigten->copy->bpow($scale);
        my ($neg, $pos) = (
            # bdiv returns (quo,rem) in list context :/
            scalar $bigtwo->copy->bpow($sbits)->bmul(-1)->bdiv($div),
            scalar $bigtwo->copy->bpow($sbits)->bsub(1)->bdiv($div),
        );

        my $digits = ceil( $sbits * _BASE2_LOG );
        my $emin2  = ceil( $scale / _BASE2_LOG );

        my $is_perl_safe = (
            Data::Float::significand_bits >= $sbits &&
            Data::Float::min_finite_exp   <= -$emin2
        );

        my $_NumRange_param = $_NumRange->parameterize($neg, $pos);

        Type::Tiny->new(
            display_name => "FixedBinary[$bits, $scale]",
            parent     => $self,
            library    => __PACKAGE__,
            constraint => __real_constraint_generator($is_perl_safe, $digits, $_NumRange_param, 1),
            inlined    => __real_inline_generator    ($is_perl_safe, $digits, $_NumRange_param, 1),
        );
    },
);

=head3 FixedDecimal[`d, `s]

Like L</FixedBinary[`b, `s]>, but for a C<`d> digit integer.  Or, you could think of C<`d> and C<`s> as accuracy (significant
figures) and decimal precision, respectively.

=cut

$meta->add_type(
    name       => 'FixedDecimal',
    parent     => $_RealSafeNum,
    library    => __PACKAGE__,
    # kinda pointless without the parameters
    constraint_generator => sub {
        my $self = $Type::Tiny::parameterize_type;
        my ($digits, $scale) = (shift, shift);
        $digits =~ /\A[0-9]+\z/ or _croak( "First parameter to FixedDecimal[`d, `s] expected to be a positive integer; got $digits");
        $scale  =~ /\A[0-9]+\z/ or _croak("Second parameter to FixedDecimal[`d, `s] expected to be a positive integer; got $scale");

        my $sbits = ceil( $digits / _BASE2_LOG );
        my $emin2 = ceil( $scale  / _BASE2_LOG );

        my $is_perl_safe = (
            Data::Float::significand_bits >= $sbits &&
            Data::Float::min_finite_exp   <= -$emin2
        );

        my $div = $bigten->copy->bpow($scale);
        my $max = $bigten->copy->bpow($digits)->bsub(1)->bdiv($div);

        my $_NumRange_param = $_NumRange->parameterize(-$max, $max);

        Type::Tiny->new(
            display_name => "FixedDecimal[$digits, $scale]",
            parent     => $self,
            library    => __PACKAGE__,
            constraint => __real_constraint_generator($is_perl_safe, $digits, $_NumRange_param, 1),
            inlined    => __real_inline_generator    ($is_perl_safe, $digits, $_NumRange_param, 1),
        );
    },
);

#############################################################################
# Character types

=head2 Characters

Characters are basically encoded numbers, so there's a few types here.  If you need types that handle multi-length strings, you're
better off using L<Types::Encodings>.

=head3 Char

A single character.  Unicode is supported, but it must be decoded first.  A multi-byte character that Perl thinks is two separate
characters will fail this type.

=head3 Char[`b]

A single character that fits within C<`b> bits.  Unicode is supported, but it must be decoded first.

=cut

$meta->add_type(
    name       => 'Char',
    parent     => Types::Standard::Str,
    library    => __PACKAGE__,
    constraint => sub { length($_) == 1 },  # length() will do a proper Unicode char length
    inlined    => sub {
        my ($self, $val) = @_;
        undef, "length($val) == 1";
    },
    constraint_generator => sub {
        my $self = $Type::Tiny::parameterize_type;
        my ($bits) = (shift);
        $bits =~ /\A[0-9]+\z/ or _croak("Parameter to Char[`b] expected to be a positive integer; got $bits");

        Type::Tiny->new(
            display_name => "Char[$bits]",
            parent     => $self,
            library    => __PACKAGE__,
            constraint => sub { ord($_) < 2**$bits },
            inlined    => sub {
                my $val = $_[1];
                (undef, "ord($val) < 2**$bits");
            },
        );
    },
);

#############################################################################
# Types from Types::Common::Numeric

=head2 Types::Common::Numeric analogues

The L<Types::Common::Numeric> module has a lot of useful types, but none of them are compatible with blessed numbers.  This module
re-implements them to be grandchildren of L</NumLike> and L</IntLike>, which allows blessed numbers.

Furthermore, the L</NumRange> and L</IntRange> checks are already implemented and described above.

=head3 PositiveNum

Accepts non-zero numbers in the positive range.

=cut

$meta->add_type(
    name    => 'PositiveNum',
    parent  => $_NumRange->parameterize(0, undef, 1),
    message => sub { "Must be a positive number" },
);

=head3 PositiveOrZeroNum

Accepts numbers in the positive range, or zero.

=cut

$meta->add_type(
    name    => 'PositiveOrZeroNum',
    parent  => $_NumRange->parameterize(0),
    message => sub { "Must be a number greater than or equal to zero" },
);

=head3 PositiveInt

Accepts non-zero integers in the positive range.

=cut

$meta->add_type(
    name    => 'PositiveInt',
    parent  => $_IntRange->parameterize(1),
    message => sub { "Must be a positive integer" },
);

=head3 PositiveOrZeroInt

Accepts integers in the positive range, or zero.

=cut

$meta->add_type(
    name    => 'PositiveOrZeroInt',
    parent  => $_IntRange->parameterize(0),
    message => sub { "Must be an integer greater than or equal to zero" },
);

=head3 NegativeNum

Accepts non-zero numbers in the negative range.

=cut

$meta->add_type(
    name    => 'NegativeNum',
    parent  => $_NumRange->parameterize(undef, 0, undef, 1),
    message => sub { "Must be a negative number" },
);

=head3 NegativeOrZeroNum

Accepts numbers in the negative range, or zero.

=cut

$meta->add_type(
    name    => 'NegativeOrZeroNum',
    parent  => $_NumRange->parameterize(undef, 0),
    message => sub { "Must be a number less than or equal to zero" },
);

=head3 NegativeInt

Accepts non-zero integers in the negative range.

=cut

$meta->add_type(
    name    => 'NegativeInt',
    parent  => $_IntRange->parameterize(undef, -1),
    message => sub { "Must be a negative integer" },
);

=head3 NegativeOrZeroInt

Accepts integers in the negative range, or zero.

=cut

$meta->add_type(
    name    => 'NegativeOrZeroInt',
    parent  => $_IntRange->parameterize(undef, 0),
    message => sub { "Must be an integer less than or equal to zero" },
);

=head3 SingleDigit

Accepts integers between -9 and 9.

=cut

$meta->add_type(
    name    => 'SingleDigit',
    parent  => $_IntRange->parameterize(-9, 9),
    message => sub { "Must be a single digit" },
);

42;
