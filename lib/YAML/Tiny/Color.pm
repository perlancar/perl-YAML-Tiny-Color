package YAML::Tiny::Color;

use 5.010;
use strict;
use warnings;

use Carp;
use Scalar::Util qw(looks_like_number refaddr);
use Term::ANSIColor qw(:constants);

require Exporter;
our @ISA    = qw(Exporter);
our @EXPORT = qw(Dump);

# VERSION

our $LineNumber = 0;

# The character class of all characters we need to escape
# NOTE: Inlined, since it's only used once
# my $RE_ESCAPE = '[\\x00-\\x08\\x0b-\\x0d\\x0e-\\x1f\"\n]';

# Printed form of the unprintable characters in the lowest range
# of ASCII characters, listed by ASCII ordinal position.
my @UNPRINTABLE = qw(
                        z    x01  x02  x03  x04  x05  x06  a
                        x08  t    n    v    f    r    x0e  x0f
                        x10  x11  x12  x13  x14  x15  x16  x17
                        x18  x19  x1a  e    x1c  x1d  x1e  x1f
                );

# Printable characters for escapes
my %UNESCAPES = (
    z => "\x00", a => "\x07", t    => "\x09",
    n => "\x0a", v => "\x0b", f    => "\x0c",
    r => "\x0d", e => "\x1b", '\\' => '\\',
);

# Special magic boolean words
my %QUOTE = map { $_ => 1 } qw{
                                  null Null NULL
                                  y Y yes Yes YES n N no No NO
                                  true True TRUE false False FALSE
                                  on On ON off Off OFF
                          };

our %theme = (
    start_quote         => BOLD . BRIGHT_GREEN,
    end_quote           => RESET,
    start_string        => GREEN,
    end_string          => RESET,
    # currently not highlighted
    #start_string_escape => BOLD,
    #end_string_escape   => RESET . GREEN, # back to string
    start_number        => BOLD . BRIGHT_MAGENTA,
    end_number          => RESET,
    start_bool          => CYAN,
    end_bool            => RESET,
    start_null          => CYAN,
    end_null            => RESET,
    start_hash_key      => MAGENTA,
    end_hash_key        => RESET,
    #start_hash_key_escape => BOLD,
    #end_hash_key_escape   => RESET . MAGENTA, # back to object key
    start_linum         => REVERSE . WHITE,
    end_linum           => RESET,
);

sub new {
    my $class = shift;
    bless [ @_ ], $class;
}

# Save an object to a string
sub _write_string {
    my $self = shift;
    return '' unless @$self;

    # Iterate over the documents
    my $indent = 0;
    my @lines  = ();
    foreach my $cursor ( @$self ) {
        push @lines, '---';

        # An empty document
        if ( ! defined $cursor ) {
            # Do nothing

            # A scalar document
        } elsif ( ! ref $cursor ) {
            $lines[-1] .= ' ' . $self->_write_scalar( $cursor, $indent );

            # A list at the root
        } elsif ( ref $cursor eq 'ARRAY' ) {
            unless ( @$cursor ) {
                $lines[-1] .= ' []';
                next;
            }
            push @lines, $self->_write_array( $cursor, $indent, {} );

            # A hash at the root
        } elsif ( ref $cursor eq 'HASH' ) {
            unless ( %$cursor ) {
                $lines[-1] .= ' {}';
                next;
            }
            push @lines, $self->_write_hash( $cursor, $indent, {} );

        } else {
            Carp::croak("Cannot serialize " . ref($cursor));
        }
    }

    join '', map { "$_\n" } @lines;
}

sub _write_scalar {
    my $string = $_[1];
    my $is_hkey = $_[3];

    my ($sq, $eq, $ss, $es);
    if ($is_hkey) {
        $sq = $theme{start_hash_key};
        $eq = $theme{end_hash_key};
        $ss = $theme{start_hash_key};
        $es = $theme{end_hash_key};
    } else {
        $sq = $theme{start_quote};
        $eq = $theme{end_quote};
        $ss = $theme{start_string};
        $es = $theme{end_string};
    }

    return $theme{start_null}.'~'.$theme{end_null} unless defined $string;
    return $theme{start_quote}."''".$theme{end_quote} unless length  $string;
    if ( $string =~ /[\x00-\x08\x0b-\x0d\x0e-\x1f\"\'\n]/ ) {
        $string =~ s/\\/\\\\/g;
        $string =~ s/"/\\"/g;
        $string =~ s/\n/\\n/g;
        $string =~ s/([\x00-\x1f])/\\$UNPRINTABLE[ord($1)]/g;
        return join(
            "",
            $sq, '"', $eq,
            $ss, $string, $es,
            $sq, '"', $eq,
        );
    }
    if ( $string =~ /(?:^\W|\s|:\z)/ or $QUOTE{$string} ) {
        return join(
            "",
            $sq, "'", $eq,
            $ss, $string, $es,
            $sq, "'", $eq,
        );
    }
    return join("", $ss, $string, $es);
}

sub _write_array {
    my ($self, $array, $indent, $seen) = @_;
    if ( $seen->{refaddr($array)}++ ) {
        die "YAML::Tiny::Color does not support circular references";
    }
    my @lines  = ();
    foreach my $el ( @$array ) {
        my $line = ('  ' x $indent) . '-';
        my $type = ref $el;
        if ( ! $type ) {
            $line .= ' ' . $self->_write_scalar( $el, $indent + 1 );
            push @lines, $line;

        } elsif ( $type eq 'ARRAY' ) {
            if ( @$el ) {
                push @lines, $line;
                push @lines, $self->_write_array( $el, $indent + 1, $seen );
            } else {
                $line .= ' []';
                push @lines, $line;
            }

        } elsif ( $type eq 'HASH' ) {
            if ( keys %$el ) {
                push @lines, $line;
                push @lines, $self->_write_hash( $el, $indent + 1, $seen );
            } else {
                $line .= ' {}';
                push @lines, $line;
            }

        } else {
            die "YAML::Tiny::Color does not support $type references";
        }
    }

    @lines;
}

sub _write_hash {
    my ($self, $hash, $indent, $seen) = @_;
    if ( $seen->{refaddr($hash)}++ ) {
        die "YAML::Tiny::Color does not support circular references";
    }
    my @lines  = ();
    foreach my $name ( sort keys %$hash ) {
        my $el   = $hash->{$name};
        my $line = ('  ' x $indent) . $self->_write_scalar($name, 0, 1) . ":";
        my $type = ref $el;
        if ( ! $type ) {
            $line .= ' ' . $self->_write_scalar( $el, $indent + 1 );
            push @lines, $line;

        } elsif ( $type eq 'ARRAY' ) {
            if ( @$el ) {
                push @lines, $line;
                push @lines, $self->_write_array( $el, $indent + 1, $seen );
            } else {
                $line .= ' []';
                push @lines, $line;
            }

        } elsif ( $type eq 'HASH' ) {
            if ( keys %$el ) {
                push @lines, $line;
                push @lines, $self->_write_hash( $el, $indent + 1, $seen );
            } else {
                $line .= ' {}';
                push @lines, $line;
            }

        } else {
            die "YAML::Tiny::Color does not support $type references";
        }
    }

    @lines;
}

sub Dump {
    my $res = YAML::Tiny::Color->new(@_)->_write_string;

    if ($YAML::Tiny::Color::LineNumber) {
        my $lines = 0;
        $lines++ while $res =~ /^/mog;
        my $fmt = "%".length($lines)."d";
        my $i = 0;
        $res =~ s/^/
            $theme{start_linum} . sprintf($fmt, ++$i) . $theme{end_linum}
                /meg;
    }
    $res;
}

1;
# ABSTRACT: Dump YAML with color

=for Pod::Coverage ^(new)$

=head1 SYNOPSIS

 use YAML::Tiny::Color;
 say Dump({your => "data"});


=head1 DESCRIPTION

This module dumps your data structure as YAML with color using ANSI escape
sequences. To change the colors, see C<%theme> in source code.


=head1 VARIABLES

=head2 $YAML::Tiny::Color::LineNumber => BOOL (default: 0)

Whether to include line numbers in dumps.

=head1 FUNCTIONS

=head2 Dump

Exported by default. Dump data as YAML. Die on errors.


=head1 ACKNOWLEDGEMENTS

YAML dumping code stolen from L<YAML::Tiny> (1.51).


=head1 SEE ALSO

L<JSON::Color>

At the time of this writing, none of syntax highlighting libraries on CPAN
support YAML. For alternatives, you might want to take a look at Python's
Pygments or Ruby's coderay.

=cut
