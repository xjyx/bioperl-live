# $Id$
#
# BioPerl module for Bio::SeqIO::tigrcoordset
#
# Cared for by Jason Stajich <jason-at-bioperl-dot-org>
#
# Copyright Jason Stajich
#
# You may distribute this module under the same terms as perl itself

# POD documentation - main docs before the code

=head1 NAME

Bio::SeqIO::tigrcoordset - Parse TIGR (new) XML 

=head1 SYNOPSIS

  use Bio::SeqIO;
  my $in = new Bio::SeqIO(-format => 'tigrcoordset',
                          -file   => 'file.xml');
  while( my $seq = $in->next_seq ) {
  }

=head1 DESCRIPTION

This is a parser for TIGR XML.  It seems to be a newer version than
the current TIGR XML.

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
email or the web:

  bioperl-bugs@bioperl.org
  http://bioperl.org/bioperl-bugs/

=head1 AUTHOR - Jason Stajich

Email jason-at-bioperl-dot-org

Describe contact details here

=head1 CONTRIBUTORS

Additional contributors names and emails here

=head1 APPENDIX

The rest of the documentation details each of the object methods.
Internal methods are usually preceded with a _

=cut


# Let the code begin...


package Bio::SeqIO::tigrxml;
use vars qw(@ISA $Default_Source);
use strict;
use Bio::SeqIO;
use XML::SAX;
use XML::SAX::Writer;
use XML::SAX::Base;
use Data::Dumper;
use Bio::Seq::SeqFactory;
use Bio::Species;
use Bio::SeqFeature::Generic;
use Bio::Annotation::Reference;
use Bio::Annotation::DBLink;

@ISA = qw( Bio::SeqIO XML::SAX::Base);


$Default_Source = 'TIGR';

sub _initialize {
    my ($self) = shift;
    $self->SUPER::_initialize(@_);
    $self->{'_parser'} = XML::SAX::ParserFactory->parser('Handler' => $self);
    if( ! defined $self->sequence_factory ) {
	$self->sequence_factory(new Bio::Seq::SeqFactory
				(-verbose => $self->verbose(), 
				 -type => 'Bio::Seq::RichSeq'));
    }
    return;
}

sub next_seq {    
    my $self = shift;
    if( @{$self->{'_seendata'}->{'_seqs'} || []} || 
	eof($self->_fh)) { 
	return shift @{$self->{'_seendata'}->{'_seqs'}};
    }
    $self->{'_parser'}->parse_file($self->_fh);
    return shift @{$self->{'_seendata'}->{'_seqs'}};
}

# XML::SAX::Base methods

sub start_document {
    my ($self,$doc) = @_;
    $self->{'_seendata'} = {'_seqs'    => [],
			    '_authors' => [],
			    '_feats'   => [] };
    $self->SUPER::start_document($doc);
}

sub end_document { 
    my ($self,$doc) = @_;
    $self->SUPER::end_document($doc);
}

sub start_element {
    my ($self,$ele) = @_;
    # attributes
    my $name = $ele->{'LocalName'};
    my $attr = $ele->{'Attributes'};
    my $seqid = defined $self->{'_seendata'}->{'_seqs'}->[-1] ? 
	$self->{'_seendata'}->{'_seqs'}->[-1]->display_id : undef;
	
    # we're going to try and be SO-nice here
    if( $name eq 'ASSEMBLY' ) { # New sequence
	my ($len) = $attr->{'{}COORDS'}->{'Value'} =~ /\d+\-(\d+)/;
	push @{$self->{'_seendata'}->{'_seqs'}},
	$self->sequence_factory->create
	    (
	     -primary_id => $attr->{'ASMBL_ID'},
	     -length     => $len,
	     );
    } elsif( $name eq 'HEADER' ) { 
    } elsif( $name eq 'CLONE_NAME' ) {
    } elsif( $name eq 'ORGANISM' ) { 
    } elsif( $name eq 'AUTHOR_LIST' ) {
	$self->{'_seendata'}->{'_authors'} = [];
    } elsif( $name eq 'TU' ) { # gene feature
	my ($s,$e) = ($attr->{'{}COORDS'}->{'Value'} =~ /(\d+)\-(\d+)/);
	my $strand = 1;
	if( $s > $e) { 
	    ($s,$e,$strand) = ( $e,$s,-1);
	}
	
	my $f = Bio::SeqFeature::Generic->new
	    (-seq_id      => $seqid,
	     -start       => $s,
	     -end         => $e,
	     -strand      => $strand,
	     -primary_tag => 'gene', # what does this really map to?
	     -source_tag  => $Default_Source,
	     -tag         => { 
		 'Note'         => $attr->{'{}COM_NAME'}->{'Value'},
		 'ID'           => $attr->{'{}FEAT_NAME'}->{'Value'} || die,
		 'locus'        => $attr->{'{}LOCUS'}->{'Value'},
		 'pub_locus'    => $attr->{'{}PUB_LOCUS'}->{'Value'},
		 'alt_locus'    => $attr->{'{}ALT_LOCUS'}->{'Value'},
		 'pub_comment'  => $attr->{'{}PUB_COMMENT'}->{'Value'},
	     }
	     );
	push @{$self->{'_seendata'}->{'_feats'}}, $f;
	# add this feature to the current sequence
	$self->{'_seendata'}->{'_seqs'}->[-1]->add_SeqFeature($f);
    } elsif( $name eq 'MODEL' ) { # mRNA/transcript
	# reset the UTRs
	$self->{'_seendata'}->{"5'-UTR"}= $self->{'_seendata'}->{"3'-UTR"}= undef;
	my ($s,$e) = ($attr->{'{}COORDS'}->{'Value'} =~ /(\d+)\-(\d+)/);
	my $strand = 1;
	if( $s > $e) { 
	    ($s,$e,$strand) = ( $e,$s,-1);
	}
	my $parent = $self->{'_seendata'}->{'_feats'}->[-1];
	my ($parentid) = $parent->get_tag_values('ID');
	my $f = Bio::SeqFeature::Generic->new
	    (-primary_tag => 'transcript',
	     -source_tag  => $Default_Source,
	     -start       => $parent->start,	     
	     -end         => $parent->end, 
	     -strand      => $strand,
	     -seq_id      => $seqid,
	     -tag         => {
		 'ID'     => $attr->{'{}FEAT_NAME'}->{'Value'},
		 'Parent' => $parentid,
		 'Note'   => $attr->{'{}COMMENT'}->{'Value'},
	     });
	$parent->add_SeqFeature($f);
	push @{$self->{'_seendata'}->{'_feats'}}, $f;
	$self->{'_seendata'}->{'_seqs'}->[-1]->add_SeqFeature($f);
    } elsif( $name eq 'EXON' ) { # exon feature
	my ($s,$e) = ($attr->{'{}COORDS'}->{'Value'} =~ /(\d+)\-(\d+)/);
	my $strand = 1;
	if( $s > $e) { 
	    ($s,$e,$strand) = ( $e,$s,-1);
	}
	my $parent = $self->{'_seendata'}->{'_feats'}->[-1];
	
	my ($parentid) = $parent->get_tag_values('ID');	

	my $f = Bio::SeqFeature::Generic->new
	    (-primary_tag => 'exon',
	     -source_tag  => $Default_Source,
	     -seq_id      => $seqid,
	     -start       => $s,
	     -end         => $e, 
	     -strand      => $strand,
	     -tag         => {
		 'ID'     => $attr->{'{}FEAT_NAME'}->{'Value'},
		 'Parent' => $parentid,
	     });
	$parent->add_SeqFeature($f);
	$self->{'_seendata'}->{'_seqs'}->[-1]->add_SeqFeature($f);
	# we'll still just add exons to the transcript 
    } elsif( $name eq 'PROTEIN_SEQ' ) { 
	
    } elsif( $name eq 'CDS' ) {
	# CDS will be the translation of the transcript
	my ($s,$e) = ($attr->{'{}COORDS'}->{'Value'} =~ /(\d+)\-(\d+)/);
	my $strand = 1;
	if( $s > $e) { 
	    ($s,$e,$strand) = ( $e,$s,-1);
	}
	my $parent = $self->{'_seendata'}->{'_feats'}->[-1];
	my ($parentid) = $parent->get_tag_values('ID');
	$self->assert($parent->primary_tag eq 'transcript', 'Testing for primary tag equivalent to mRNA');
	$self->assert($parent->strand == $strand || abs($s-$e) == 0, 'Testing that parent feature and current feature strand are equal '. $parentid. ' '.$attr->{'{}FEAT_NAME'}->{'Value'});
	my $f = Bio::SeqFeature::Generic->new
	    (-primary_tag => 'CDS',
	     -source_tag  => $Default_Source,
	     -seq_id      => $seqid,
	     -start       => $s,
	     -end         => $e, 
	     -strand      => $parent->strand,
	     -tag         => {
		 'ID'     => $attr->{'{}FEAT_NAME'}->{'Value'},
		 'Parent' => $parentid, # should be the mRNA
	     });
	$parent->add_SeqFeature($f);
	$self->{'_seendata'}->{'_seqs'}->[-1]->add_SeqFeature($f);	    
    } elsif( $name eq 'RNA-EXON' ) {

	my ($s,$e) = ($attr->{'{}COORDS'}->{'Value'} =~ /(\d+)\-(\d+)/);
	my $strand = 1;
	if( $s > $e) { 
	    ($s,$e,$strand) = ( $e,$s,-1);
	}
	my $parent = $self->{'_seendata'}->{'_feats'}->[-1];
	my ($parentid) = $parent->get_tag_values('ID');
	my $f = Bio::SeqFeature::Generic->new
	    (-primary_tag => 'tRNA_exon', # tRNA_exon?
	     -source_tag  => $Default_Source,
	     -seq_id      => $seqid,
	     -start       => $s,
	     -end         => $e, 
	     -strand      => $strand,
	     -tag         => {
		 'ID'     => $attr->{'{}FEAT_NAME'}->{'Value'},
		 'Parent' => $parentid,
	     }
	     );
	$parent->add_SeqFeature($f);
	$self->{'_seendata'}->{'_seqs'}->[-1]->add_SeqFeature($f);
    } elsif( $name eq 'PRE-TRNA' ) { # tRNA gene
	my ($s,$e) = ( $attr->{'{}COORDS'}->{'Value'} =~/(\d+)\-(\d+)/);
	my $strand = 1;
	if( $s > $e) { 
	    ($s,$e,$strand) = ( $e,$s,-1);
	}
	my $f = Bio::SeqFeature::Generic->new
	    ( -primary_tag => 'tRNA_coding_gene',
	      -source_tag  => $Default_Source,
	      -seq_id      => $seqid,
	      -start       => $s,
	      -end         => $e,
	      -strand      => $strand,
	      -tag         => {'ID' => $attr->{'{}FEAT_NAME'}->{'Value'}, 
			   }
	      );
	push  @{$self->{'_seendata'}->{'_feats'}}, $f;	
	$self->{'_seendata'}->{'_seqs'}->[-1]->add_SeqFeature($f);	
    } elsif( $name eq 'TRNA' ) { # tRNA transcript
	my ($s,$e) = ($attr->{'{}COORDS'}->{'Value'} =~ /(\d+)\-(\d+)/);
	my $strand = 1;
	if( $s > $e) { 
	    ($s,$e,$strand) = ( $e,$s,-1);
	}
	my $parent = $self->{'_seendata'}->{'_feats'}->[-1];
	my ($parentid) = $parent->get_tag_values('ID');
	my $f = Bio::SeqFeature::Generic->new
	    (-primary_tag => 'tRNA_primary_transcript',
	     -source_tag  => $Default_Source,
	     -start       => $s,
	     -end         => $e, 
	     -strand      => $strand,
	     -seq_id      => $seqid,
	     -tag         => {
		 'ID'     => $attr->{'{}FEAT_NAME'}->{'Value'},
		 'Parent' => $parentid,
		 'Note'   => $attr->{'{}COM_NAME'}->{'Value'},
		 'anticodon' => $attr->{'{}ANTICODON'}->{'Value'},
		 'pub_locus' => $attr->{'{}PUB_LOCUS'}->{'Value'},

	     });
	$parent->add_SeqFeature($f);
	push  @{$self->{'_seendata'}->{'_feats'}}, $f;	
	$self->{'_seendata'}->{'_seqs'}->[-1]->add_SeqFeature($f);
    } elsif( $name eq 'REPEAT_LIST' ) {
    } elsif( $name eq 'REPEAT' ) {
	my ($s,$e) = ($attr->{'{}COORDS'}->{'Value'} =~ /(\d+)\-(\d+)/);
	my $strand = 1;
	if( $s > $e) { 
	    ($s,$e,$strand) = ( $e,$s,-1);
	}
	my $f = Bio::SeqFeature::Generic->new
	    (-primary_tag => 'simple_repeat',
	     -source_tag  => $Default_Source,
	     -seq_id      => $seqid,
	     -start       => $s,
	     -end         => $e, 
	     -stand       => $strand,
	     -tag         => {
		 'ID'     => $attr->{'{}FEAT_NAME'}->{'Value'},
	     });

	push @{$self->{'_seendata'}->{'_feats'}}, $f;
	$self->{'_seendata'}->{'_seqs'}->[-1]->add_SeqFeature($f);	
    } else { 
	$self->warn("Unknown element $name, ignored\n");
    }
    push @{$self->{'_state'}}, $name;
    $self->SUPER::start_element($ele);
}

sub end_element {
    my ($self,$ele) = @_;
    pop @{$self->{'_state'}};
    my $name = $ele->{'LocalName'};
    my $curseq = $self->{'_seendata'}->{'_seqs'}->[-1];
    if( $name eq 'AUTHOR_LIST' ) {
	if( $curseq->can('annotation') ) {
	    $curseq->annotation->add_Annotation
		('reference',Bio::Annotation::Reference->new
		 (-authors => join(',',@{$self->{'_seendata'}->{'_authors'}}))
		 );	    
	}
	$self->{'_seendata'}->{'_authors'} = [];
    } elsif( $name eq 'ASSEMBLY' ) {
	if( @{$self->{'_seendata'}->{'_feats'} || []} ) {
	    $self->warn("Leftover features which were not finished!");
	}
	$self->debug("end element for ASSEMBLY ". $curseq->display_id. "\n");
    } elsif( $name eq 'TU' || 
	     $name eq 'TRNA'  || $name eq 'PRE-TRNA' || 
	     $name eq 'REPEAT' ) {
	pop @{$self->{'_seendata'}->{'_feats'}};
    } elsif( $name eq 'MODEL' ) {
	# This is all to for adding UTRs	

	my $model = pop @{$self->{'_seendata'}->{'_feats'}};
	my $curseq = $self->{'_seendata'}->{'_seqs'}->[-1];
	# sort smallest to largest, don't forget about 
	# strandedness
	my ($parentid) = $model->get_tag_values('Parent');	

	my @features = $model->get_SeqFeatures();
	my @exons = sort { $a->start <=> $b->start } 
  	            grep { $_->primary_tag eq 'exon' } @features;
	
        my @cdsexons = sort { $a->start <=> $b->start } 
	               grep { $_->primary_tag eq 'CDS' } @features;
	
	# look at the exons, find those which come after the model start
	my $cdsexon = shift @cdsexons;	
	my $exon = shift @exons; # first exon
		if( ! defined $cdsexon ) { 
	    $self->warn( "no CDS exons $parentid!");
	    return;
	} elsif( ! defined $exon ) { 
	    $self->warn("no exons $parentid!" );
	    return;
	}
	my $utrct = 1;
	while( defined $exon && $exon->start < $cdsexon->start ) {
	    my ($pid) = $exon->get_tag_values('Parent');
	    $self->debug("LeftPhase: tu-id $parentid mrna-id $pid exon is ".
			 $exon->location->to_FTstring. 
			 " CDSexon is ".$cdsexon->location->to_FTstring."\n");
	    
	    my $utr = Bio::SeqFeature::Generic->new
	       (-seq_id      => $exon->seq_id,
		-strand      => $exon->strand,
		-primary_tag => $exon->strand > 0 ? "5'-UTR" : "3'-UTR",
		-source_tag  => $Default_Source,
		-tag         => { 
		    'ID'     => "$pid.UTR".$utrct++,
		    'Parent' => $pid },
		);
	    my ($ns,$ne) = $exon->union($cdsexon);
	    $utr->start($ns); $utr->end($ne);	    
	    $model->add_SeqFeature($utr);
	    $curseq->add_SeqFeature($utr);
	    $exon = shift @exons;
	}
	@exons = sort { $a->start <=> $b->start } 
	         grep {$_->primary_tag eq 'exon' } @features;
        @cdsexons = sort { $a->start <=> $b->start } 
	            grep { $_->primary_tag eq 'CDS' } @features;
	
	$cdsexon = pop @cdsexons;
	$exon = pop @exons;
	if( ! defined $cdsexon ) { 
	    $self->warn( "no CDS exons $parentid!");
	    return;
	} elsif( ! defined $exon ) { 
	    $self->warn("no exons $parentid!" );
	    return;
	}
	$utrct = 1;
	while( defined $exon &&$exon->end > $cdsexon->end ) { 
	    my ($pid) = $exon->get_tag_values('Parent');
	    $self->debug("RightPhase: tu-id $parentid mrna-id $pid exon is ".
			 $exon->location->to_FTstring. 
			 " CDSexon is ".$cdsexon->location->to_FTstring."\n");
	    
	    my $utr = Bio::SeqFeature::Generic->new
	       (-seq_id      => $exon->seq_id,
		-strand      => $exon->strand,
		-primary_tag => $exon->strand < 0 ? "5'-UTR" : "3'-UTR",
		-source_tag  => $Default_Source,
		-tag         => { 
		    'Parent' => $pid,
		    'ID'     => "$pid.UTR".$utrct++,
		}
		);
	    my ($ns,$ne) = $exon->union($cdsexon);
	    $utr->start($ns); $utr->end($ne);

	    $model->add_SeqFeature($utr);
	    $curseq->add_SeqFeature($utr);
	    $exon = pop @exons;
	}
    }
    $self->SUPER::end_element($ele);
}

sub characters {
    my ($self,$data) = @_;
    if( ! @{$self->{'_state'}} ) {
	$self->warn("Calling characters with no previous start_element call. Ignoring data");
    } else { 
	my $curseq = $self->{'_seendata'}->{'_seqs'}->[-1];
	my $curfeat = $self->{'_seendata'}->{'_feats'}->[-1];
	my $name = $self->{'_state'}->[-1];	
	if( defined $curseq ) { 
	    if( $name eq 'CLONE_NAME' ) {
		$self->debug("Clone name is ",$data->{'Data'}, "\n");
		$curseq->display_id($data->{'Data'});
	    } elsif( $name eq 'ORGANISM' ) { 
		$curseq->species(Bio::Species->new
				 (
				  -classification => [split(/\s+/,
							    $data->{'Data'})]
				  ));
	    } elsif( $name eq 'AUTHOR' ) {
		push @{$self->{'_seendata'}->{'_authors'}}, $data->{'Data'};
	    }
	}
	if( defined $curfeat ) {
	    if( $name eq 'EXON' ) { # exon feature
	    } elsif( $name eq 'RNA-EXON' ) {
		
	    } elsif( $name eq 'PROTEIN_SEQ' ) { 
		$curfeat->add_tag_value('translation',$data->{'Data'});
	    } elsif( $name eq 'CDS' ) {
	    } elsif( $name eq 'PRE-TRNA' ) { # tRNA gene
	    } elsif( $name eq 'TRNA' ) { # tRNA transcript
	    } elsif( $name eq 'REPEAT_LIST' ) {
	    } elsif( $name eq 'REPEAT' ) {
		$curfeat->add_tag_value('Note',$data->{'Data'});
	    }
	}
    }
    $self->SUPER::characters($data);
}


sub assert { 
    my ($self,$test,$msg) = @_;
    $self->throw($msg) unless $test;
}
1;
