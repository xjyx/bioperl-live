# $Id$
#
# BioPerl module for Bio::FeatureIO::gtf
#
# Cared for by Allen Day <allenday@ucla.edu>
#
# Copyright Allen Day
#
# You may distribute this module under the same terms as perl itself

# POD documentation - main docs before the code

=head1 NAME

Bio::FeatureIO::gtf - read write features in GTF format

=head1 SYNOPSIS

L<Bio::FeatureIO::gff>

=head1 DESCRIPTION

GTF, is also known as GFF v2.5.  This class is simply a subclass
of Bio::FeatureIO::gff that initializes with -version =E<gt> 2.5.

=head1 FEEDBACK

=head2 Mailing Lists

User feedback is an integral part of the evolution of this and other
Bioperl modules. Send your comments and suggestions preferably to
the Bioperl mailing list.  Your participation is much appreciated.

  bioperl-l@bioperl.org              - General discussion
  http://bioperl.org/MailList.shtml  - About the mailing lists

=head2 Reporting Bugs

Report bugs to the Bioperl bug tracking system to help us keep track
of the bugs and their resolution. Bug reports can be submitted via
the web:

  http://bugzilla.bioperl.org/

=head1 AUTHOR - Allen Day

Email allenday@ucla.edu

Describe contact details here

=head1 CONTRIBUTORS

Additional contributors names and emails here

=head1 APPENDIX

The rest of the documentation details each of the object methods.
Internal methods are usually preceded with a _

=cut


# Let the code begin...


package Bio::FeatureIO::gtf;
use base qw(Bio::FeatureIO::gff);
use strict;

# Object preamble - inherits from Bio::Root::Root

sub initialize {
  my($self,%arg) = @_;
  $arg{-version} = 2.5;
  $self->SUPER::_initialize(%arg);
  return 1;
}

1;
