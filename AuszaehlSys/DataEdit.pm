# Database-Handling
# $Id: DataEdit.pm 151 2009-01-27 17:56:16Z mariop $
#
# (c) 2003, 2004        Kristof Koehler <Kristof.Koehler@stud.uni-karlsruhe.de>
#
# Published under GPL

package DataEdit;
use Exporter ();
@ISA       = qw(Exporter);
@EXPORT    = qw(DataEdit);

use strict ;

use ForeignKeys ;
use KKOptions ;

sub DataEdit {
    my $this = {
	can_delete => 1
    } ;
    bless $this ;
    do_options ( {@_}, $this, 
		 "dbh",
		 "-foreign",
		 "select_fields",
		 "select_from",
		 "-select_where",
		 "-select_order",
		 "-default_row",
		 "-can_delete",
		 "edit_table",
		 "id_column",
		 "-fixed" ) ;
    $this->{"select"} = ( "SELECT ".join(",", @{$this->{"select_fields"}}).
			  " FROM ".$this->{"select_from"} ) ;
    if ( defined $this->{"select_where"} ) {
	$this->{"select"} .= " WHERE ".$this->{"select_where"} ;
    }
    if ( defined $this->{"select_order"} ) {
	$this->{"select"} .= " ORDER BY ".$this->{"select_order"} ;
    }
    return $this ;
}

sub get_data {
    my $this = shift ;
    my $dbh = $this->{"dbh"} ;
    my $sth = $dbh->prepare($this->{"select"}) ;
    #print $this->{"select"};
    my $aref = [] ;
    if ( defined $sth && $sth->execute ) {
	my $rowref ;
	while ( defined ( $rowref = $sth->fetchrow_arrayref ) ) {
	    my $href = {} ;
	    my $fieldsref = $this->{"select_fields"} ;
	    my $i ;
	    for ( $i = 0 ; $i < scalar(@$fieldsref) ; $i++ ) {
		$href->{$fieldsref->[$i]} = $rowref->[$i] ;
	    }
	    push @$aref, $href ;
	}
    }
    if ( defined $this->{"default_row"} ) {
	push @$aref, { %{$this->{"default_row"}} } ;
    }
    return $aref ;
} ;

sub set_data {
    my $this = shift ;
    my ( $dataref, $column ) = @_ ;

    my $dbh = $this->{"dbh"} ;
    my $id = $dataref->{$this->{"id_column"}} ;

    my %newrow = ( $column => $dataref->{$column} ) ;

    if ( defined $this->{"fixed"} ) {
	my $f ;
	foreach $f ( @{$this->{"fixed"}} ) {
	    $dataref->{$f->[0]} = 
		$f->[2] ? $f->[1] : $dataref->{$f->[1]} ;
	    $newrow{$f->[0]} = $dataref->{$f->[0]} ;
	}
    }

    if ( defined $id ) {
	UpdateChecked ( $dbh, $this->{"foreign"}, $this->{"edit_table"},
			\%newrow, $this->{"id_column"}."=".$dbh->quote($id)) ;
    } else {
	if ( InsertChecked ( $dbh, $this->{"foreign"}, $this->{"edit_table"},
			     \%newrow ) ) {
	    $dataref->{$this->{"id_column"}} = 
		$dbh->selectrow_array("SELECT LAST_INSERT_ID()") ;
	}
    }
}

sub delete_data {
    my $this = shift ;
    my ( $dataref ) = @_ ;
    my $dbh = $this->{"dbh"} ;
    my $id = $dataref->{$this->{"id_column"}} ;
    if ( defined $id ) {
	DeleteCascade ( $dbh, $this->{"foreign"},
			$this->{"edit_table"}, 
			$this->{"id_column"}."=".$dbh->quote($id) ) ;
	$dataref->{$this->{"id_column"}} = undef ;
    }
}

sub id_column {
    my $this = shift ;
    return $this->{"id_column"} ;
}

