# Wahlauswertung
# $Id: Auswertung.pm 469 2011-01-21 18:12:27Z rosi $
#
# (c) 2003, 2004        Kristof Koehler <Kristof.Koehler@stud.uni-karlsruhe.de>
#
# Published under GPL

package Auswertung;
use Exporter ();

@ISA       = qw(Exporter);
@EXPORT_OK = qw(DoWahlen DoListen DoKandidaten UrnePruefen);

use strict;
use warnings;

use POSIX 'ceil' ;

my $OK_STATUS = 4;

sub DoWahlen {
    my ( $dbh ) = @_ ;
    my ( $qry ) = $dbh->prepare 
	( "SELECT wahl.id, sitze, max_stimmen, max_kumulieren FROM wahl" ) ;
    $qry->execute ;
    while ( my($id, $sitze, $max_stimmen, $max_kumulieren) 
	    = $qry->fetchrow_array ) {
	my ( $sitze_wert ) = DoNumber($sitze,$dbh,$id) ;
	my ( $max_stimmen_wert ) = DoNumber($max_stimmen,$dbh,$id) ;
	my ( $max_kumulieren_wert ) = DoNumber($max_kumulieren,$dbh,$id) ;
	$dbh->do("UPDATE wahl SET ".
		 "sitze_wert          = $sitze_wert, ".
		 "max_stimmen_wert    = $max_stimmen_wert,".
		 "max_kumulieren_wert = $max_kumulieren_wert ".
		 "WHERE id = $id") ;
    } 
}

my %DoNumberFunctions = 
    ( 
      Listen  => sub {
	  my ($dbh,$wahl_id) = @_ ;
	  my ($listen) = 
	      $dbh->selectrow_array ( "SELECT count(*) FROM liste ".
				      "WHERE wahl = $wahl_id" ) ;
	  return $listen ;
      },

      FSStimmen => sub {
	  my ($dbh,$wahl_id) = @_ ;
	  my ($wb) = $dbh->selectrow_array 
	      ( "SELECT wahlberechtigt FROM wahl WHERE id = $wahl_id" ) ;
	  my ($kand_zahl) = $dbh->selectrow_array 
	      ( "SELECT count(*) ".
		"FROM liste, kandidat ".
		"WHERE liste.wahl     = $wahl_id ".
		"AND   kandidat.liste = liste.id " ) ;
	  my ( $stimmen ) = ceil ( $wb / 150 ) ;
	  if ( $stimmen > $kand_zahl ) {
	      $stimmen = $kand_zahl ;
	  }
	  return $stimmen ;
      },

      FSSitze => sub {
	  my ($dbh,$wahl_id) = @_ ;
	  my ($kand_gueltig) = $dbh->selectrow_array 
# Bugfix: Die Anzahl der Fachschaftsvorst�nde richtet sich nach der Anzahl der abgegebenen Stimmzettel,
# unabh�ngig davon, ob die Stimmzettel g�ltig sind oder nicht (Satzung, �36, Abs. 3).
#	      ( "SELECT SUM(stimmzettel - stimmzettel_ungueltig ".
#		"- kandidaten_ungueltig) ".
	      ( "SELECT SUM(stimmzettel) ".
		"FROM urne, wahl_urne ".
		"WHERE wahl_urne.wahl = $wahl_id ".
		"AND   wahl_urne.urne = urne.id ".
		"AND status = $OK_STATUS" ) ;
	  if ( ! defined $kand_gueltig ) {
	      $kand_gueltig = 0 ;
	  }
	  if ( $kand_gueltig <= 200 ) {
	      return 2 ;
	  } else {
	      return 2 + ceil ( ($kand_gueltig - 100) / 200 ) ;
	  }
      }
      
      ) ;

sub DoNumber {
    my ( $val, @arg ) = @_ ;
    if ( $val =~ /^[0-9\.]*$/ ) {
	return $val ;
    }
    if ( !defined $DoNumberFunctions{$val} ) {
	warn "Undefinierte Funktion: '$val'\n" ;
	return 0 ;
    }
    return &{$DoNumberFunctions{$val}}(@arg)
}

sub DoListen {
    my ( $dbh ) = @_ ;
    my $qry = $dbh->prepare ( "SELECT wahl.id, wahl.name_kurz FROM wahl" ) ;
    $qry->execute ;
    while ( my ( $id, $name ) = $qry->fetchrow_array ) {
	DoWahlListen ( $dbh, $id, $name ) ;
    } 
}

sub DoKandidaten {
    my ( $dbh ) = @_ ;
    my $qry = $dbh->prepare ( "SELECT wahl.id, wahl.name_kurz FROM wahl" ) ;
    $qry->execute ;
    while ( my ( $id, $name ) = $qry->fetchrow_array ) {
	DoWahlKandidaten ( $dbh, $id, $name ) ;
    } 
}

sub DoWahlListen {
    my ( $dbh, $wahl, $wahlname ) = @_ ;

    ## Sitze ##############################
    my ( $sitze ) = 
	$dbh->selectrow_array ( "SELECT sitze_wert FROM wahl WHERE id=$wahl" );

    ## Sitze auf Listen verteilen ##############################
    my $liste_num = $dbh->selectrow_array ( "SELECT count(*) FROM liste ".
					    "WHERE wahl = $wahl" ) ;
    if ( $liste_num == 0 ) {
	warn "Wahl $wahlname: Keine Listen\n" ;
    } elsif ( $liste_num == 1 ) {
	$dbh->do ( "UPDATE liste ".
		   "SET sitze = $sitze, los = 0 ".
		   "WHERE wahl = $wahl" ) ;
    } else {
	SainteLague ( $dbh, $wahl, $wahlname, $sitze ) ;
    }
}

###########################################################
## Ungenutzter Code - Ausz�hlverfahren hat sich ge�ndert ##
## zur UWahl 2011 - Heiko Rosemann - rosi@usta.de        ##
###########################################################
sub HareNiemeyer {
    my ( $dbh, $wahl, $wahlname, $sitze ) = @_ ;
    my $qry ;

    my $liste_FROMWHERE = ( "FROM liste, liste_urne, urne ".
			    "WHERE wahl = $wahl ".
			    "AND liste_urne.liste = liste.id ".
			    "AND liste_urne.urne = urne.id ".
			    "AND urne.status = $OK_STATUS " ) ;

    ## Stimmen Summe ##############################
    my $stimmen_summe = $dbh->selectrow_array 
	( "SELECT sum(liste_urne.stimmen) $liste_FROMWHERE" ) ;
    if ( ! defined $stimmen_summe ) {
	return ;
    }

    ## Ganzzahliger Sitzanteil ##############################
    $qry = $dbh->prepare 
	( "SELECT liste.id, ".
	  "FLOOR($sitze*sum(liste_urne.stimmen)/$stimmen_summe), ".
	  "$sitze*sum(liste_urne.stimmen)/$stimmen_summe ".
	  $liste_FROMWHERE. 
	  "GROUP BY liste.id" ) ;
    $qry->execute ;
    my $sitze_summe = 0 ;
    while ( my( $liste_id, $liste_sitze, $liste_hoechstzahl ) = $qry->fetchrow_array ) {
	$dbh->do ( "UPDATE liste ".
		   "SET sitze = $liste_sitze, los = 0, hoechstzahl = $liste_hoechstzahl ".
		   "WHERE id = $liste_id" ) ;
	$sitze_summe += $liste_sitze ;
    }
    
    ## Restsitze ##############################
    my $sitze_rest = $sitze - $sitze_summe ;

    $qry = $dbh->prepare 
	( "SELECT liste.id, ".
	  "MOD($sitze*sum(liste_urne.stimmen),$stimmen_summe) AS remain ".
	  $liste_FROMWHERE. 
	  "GROUP BY liste.id ".
	  "ORDER BY remain DESC" ) ;
    $qry->execute ;
    my @remain_ids = () ;
    my $old_remain ;
    while ( my( $liste_id, $remain ) = $qry->fetchrow_array ) {
	if ( (! defined $old_remain) || ($remain != $old_remain) ) {
	    HareNiemeyer_DoRemain ( $dbh, \@remain_ids, \$sitze_rest ) ;
	    @remain_ids = () ;
	} 
	push @remain_ids, $liste_id ;
	$old_remain = $remain ;
    }
    HareNiemeyer_DoRemain ( $dbh, \@remain_ids, \$sitze_rest ) ;
}

sub HareNiemeyer_DoRemain {
    my ( $dbh, $ids_ref, $rest_ref ) = @_ ;
    my $n = scalar(@$ids_ref) ;
    if ( $$rest_ref > 0 ) {
	if ( $$rest_ref >= $n ) {
	    foreach my $id ( @$ids_ref ) {
		$dbh->do ( "UPDATE liste SET sitze = sitze+1 ".
			   "WHERE id = $id" ) ;
	    }
	    $$rest_ref -= $n ;
	} else {
	    foreach my $id ( @$ids_ref ) {
		$dbh->do ( "UPDATE liste SET los = $$rest_ref ".
			   "WHERE id = $id" ) ;
	    }
	    $$rest_ref = 0 ;
	}
    }
}
###########################
## Ende ungenutzter Code ##
###########################

##########################################################################################
## Funktion SainteLague - verteilt Sitze nach dem H�chstzahlverfahren nach Sainte-Lague ##
## http://de.wikipedia.org/wiki/                                                        ##
## Sainte-Lagu%C3%AB-Verfahren#Berechnungsbeispiel_nach_dem_H.C3.B6chstzahlverfahren    ##
## 2011 Heiko Rosemann rosi@usta.de                                                     ##
##########################################################################################
sub SainteLague {
    my ( $dbh, $wahl, $wahlname, $sitze ) = @_ ;

    ## Collection mit H�chstzahl als Key, Listen-ID als Value ##
    my @hoechstzahlen = ();

    ## Alle Listen-IDs ##
    my @listenIDs;

    ## Listen-Informationen aus Datenbank holen ##
    my $sth = $dbh->prepare("SELECT id FROM liste WHERE wahl=$wahl");
    $sth->execute();

    ## Iteriere �ber alle Listen in der aktuellen Wahl ##
    while(my(@ref) = $sth->fetchrow_array)
    {
        ## ID der aktuellen Liste auslesen... ##
	my $listen_id = $ref[0];
        ## ...und zu Array der Listen-IDs hinzuf�gen ##
        push(@listenIDs, $listen_id);

	## Berechne in der Datenbank:                                    ##
        ## Summe aller Stimmen f�r diese Liste aus schon gez�hlten Urnen ##
	my $sth2 = $dbh->prepare("SELECT sum(liste_urne.stimmen) FROM wahl,liste_urne,urne "
				."WHERE wahl.id = $wahl "
				."AND liste_urne.urne = urne.id "
				."AND urne.status = $OK_STATUS "
				."AND liste_urne.liste = $listen_id");
	$sth2->execute();
	my $stimmen = $sth2->fetchrow();
	## Pr�fe, ob eine Zahl zur�ckgekommen ist
	if ( ($stimmen * 1) != $stimmen)
	{
	    ## wenn nicht, setze Stimmen auf Null
	    $stimmen = 0;
	}
	## Berechne f�r jede Liste genau soviele H�chstzahlen wie Sitze im Parlament insgesamt ##
	## damit nie zu wenig H�chstzahlen berechnet werden                                    ##
	## schreibe Zuordnung zwischen H�chstzahl und Listen-ID in Array                       ##
	for(my $i = 1; $i < 2 * $sitze; $i+=2)
	{
	    push(@hoechstzahlen, {hoechstzahl => $stimmen / $i, liste => $listen_id } );
        }
    }

    ## Sortiere Array nach H�chstzahlen absteigend ##
    my @sortierteHoechstzahlen = sort { $$b{'hoechstzahl'} <=> $$a{'hoechstzahl'} } @hoechstzahlen;

    ## Erstelle neue hashs f�r Sitzverteilung und Lose             ##
    my %sitzverteilung = ();
    my %lose = ();
    ## Z�hle freie Sitze mit                                       ##
    my $freieSitze = $sitze;
    ## Jede Liste hat zu Beginn 0 Sitze und muss nicht losen       ##
    foreach my $listenID (@listenIDs)
    {
	$sitzverteilung{$listenID} = 0;
	$lose{$listenID} = 0;
    }
    ## und bekommt nach H�chstzahlen zugeteilt ##
    for(my $i = 0; $i < $sitze; $i++)
    {
	## �berpr�fe, ob aktuelle H�chstzahl gleich ist mit     ##
	## erster unber�cksichtigter H�chstzahl                 ##
        ## (oder kleiner, falls Flie�komma-Artefakte auftreten) ##
	if($sortierteHoechstzahlen[$i]{'hoechstzahl'} 
	   <= $sortierteHoechstzahlen[$sitze] {'hoechstzahl'})
	{
	    ## wenn ja, muss gelost werden bis ausschlie�lich zur letzten ##
            ## H�chstzahl, die gleich der ersten unber�cksichtigten ist   ##
            ## (oder gr��er, falls Flie�komma-Artefakte auftreten)        ##
	    for(my $j = $i; 
                $sortierteHoechstzahlen[$j]{'hoechstzahl'} 
                  >= $sortierteHoechstzahlen[$sitze]{'hoechstzahl'};
		$j++)
	    {
		$lose{$sortierteHoechstzahlen[$j]{'liste'}} = 1;
	    }
	}
	else
	{
	    ## wenn nicht, bekommt die Liste, der die aktuelle H�chstzahl geh�rt, ##
	    ## einen Sitz hinzu.                                                  ##
	    $sitzverteilung{$sortierteHoechstzahlen[$i]{'liste'}}++;
	    $freieSitze--;
        }
    }

    ## L�sche Listen, die nicht losen m�ssen, aus Lose-Hash ##
    foreach my $listenID (keys %lose)
    {
        if($lose{$listenID} == 0)
	{
	    delete $lose{$listenID};
	}
    }

    ## Pr�fe, ob �berhaupt Listen losen m�ssen ##
    if(scalar(keys %lose) != 0)
    {
	## Die �brigen Sitze werden verlost.                            ##
	## Da eine Liste keine zwei gleichen H�chstzahlen hat,          ##
	## k�nnen nicht mehr gleiche H�chstzahlen als Listen auftreten. ##
	## Daher m�ssen alle Listen, deren H�chstzahl gleich der ersten ##
	## unber�cksichtigten ist, losen.				##
	foreach my $listenID (keys %lose)
	{
	    ## Speichere Zahl der freien Sitze ##
	    $lose{$listenID} = $freieSitze;
	}
    }

    ## f�r alle Listen ##
    foreach my $listenID (keys %sitzverteilung)
    {
	## Schreibe Sitzverteilung in Datenbank ##
	$dbh->do("UPDATE liste SET sitze=$sitzverteilung{$listenID} "
		 ."WHERE id=$listenID");
        ## Bei Listen, bei denen gelost werden muss ##
	if(exists $lose{$listenID})
	{
	    ## Schreibe Restsitze in Datenbank ##
	    $dbh->do("UPDATE liste SET los=$lose{$listenID} WHERE id=$listenID");
	}
	else
	{
	    ## sonst sicherheitshalber 0, falls bei fr�herer Ausz�hlung gelost worden w�re ##
	    $dbh->do("UPDATE liste SET los=0 WHERE id=$listenID");
	}
    }
}

sub DoWahlKandidaten {
    my ( $dbh, $wahl, $wahlname ) = @_ ;

    print "WAHL: $wahlname ($wahl)\n";
    my $q_liste = $dbh->prepare 
	( "SELECT id, sitze, los FROM liste WHERE wahl = $wahl" ) ;
    $q_liste->execute ;
    while ( my($liste_id, $liste_sitze, $liste_los) 
	    = $q_liste->fetchrow_array ) {
	my $q_kand = $dbh->prepare 
	    ( "SELECT kandidat.id, ".
	      "sum(kandidat_urne.stimmen) as stimmen ".
	      "FROM (kandidat, urne) ".
	      "LEFT JOIN kandidat_urne ".
	      "ON kandidat_urne.kandidat = kandidat.id ".
	      "AND urne.id = kandidat_urne.urne ".
	      "WHERE liste = $liste_id AND urne.status = $OK_STATUS ".
	      "GROUP BY kandidat.id ".
	      "ORDER BY stimmen DESC, listenplatz;" ) ;
	$q_kand->execute ;
	my $cnt = 0 ;
	while ( my($kand_id, $stimmen) = $q_kand->fetchrow_array ) {
	    if ( $cnt < $liste_sitze ) {
		$dbh->do ( "UPDATE kandidat SET status = 1 ".
			   "WHERE id = $kand_id" ) ;
	    } elsif ( ($cnt == $liste_sitze) && ($liste_los > 0) ) {
		$dbh->do ( "UPDATE kandidat SET status = 2 ".
			   "WHERE id = $kand_id" ) ;
	    } else {
		$dbh->do ( "UPDATE kandidat SET status = 3 ".
			   "WHERE id = $kand_id" ) ;
	    }
	    $cnt++ ;
	}
    }
}

sub UrnePruefen {
    my ( $dbh, $urne_id ) = @_ ;
    my $msg = "" ;

    my ( $fak, $num, $stimmen_total, $stimmen_sum ) = $dbh->selectrow_array 
	( "SELECT urne.fakultaet, urne.nummer, ".
	  "urne.stimmen, sum(wahl_urne.stimmzettel) ".
	  "FROM urne LEFT JOIN wahl_urne ON urne.id = wahl_urne.urne ".
	  "WHERE urne.id=$urne_id ".
	  "GROUP BY urne.id" ) ;
    if ( ! defined $stimmen_total ) {
	$msg .= "  Anzahl der Gesamtstimmen in der Urne fehlt!\n" ;
    } elsif ( ! defined $stimmen_sum ) {
	$msg .= "  Summe der Stimmen in der Urne ist undefiniert!\n" ;
    } elsif ( $stimmen_total != $stimmen_sum ) {
	$msg .= "  Anzahl der Stimmzettel: $stimmen_total  ".
	    "Summe der Wahl-Stimmen: $stimmen_sum\n" ;
    }

    my $qry = $dbh->prepare
	("SELECT wahl.name_kurz, ".
	 "wahl_urne.stimmzettel, wahl_urne.stimmzettel_ungueltig, ".
	 "wahl_urne.listen_ungueltig, wahl_urne.listen_enthaltungen, ".
	 "sum(liste_urne.stimmen) ".
	 "FROM wahl, liste, wahl_urne, liste_urne ".
	 "WHERE liste.wahl = wahl.id ".
	 "AND wahl_urne.wahl = wahl.id ".
	 "AND wahl_urne.urne = $urne_id ".
	 "AND liste_urne.liste = liste.id ".
	 "AND liste_urne.urne = wahl_urne.urne ".
	 "GROUP BY wahl.id") ;
    $qry->execute;
    my ( @r ) ;
    while ( @r = $qry->fetchrow_array ) {
	my ( $wahl, $zettel, $zettel_ungueltig, 
	     $liste_ungueltig, $liste_enth, $liste_summe ) = @r ;
	if ( ! defined $zettel ) {
	    $msg .= "  $wahl: Anzahl der Stimmzettel nicht definiert\n" ;
	    next ;
	}
	if ( ! defined $zettel_ungueltig ) {
	    $msg .= "  $wahl: Anzahl der ungueltigen Stimmzettel ".
		"nicht definiert\n" ;
	    next ;
	}
	if ( ! defined $liste_ungueltig ) {
	    $msg .= "  $wahl: Anzahl der ungueltigen Listenstimmen ".
		"nicht definiert\n" ;
	    next ;
	}
	my ( $gueltig ) = $zettel - $zettel_ungueltig - $liste_ungueltig ;
	if ( $gueltig < 0 ) {
	    $msg .= "  $wahl: Mehr ungueltige Stimmen als Stimmzettel\n" ;
	}
	if ( ! defined $liste_enth ) {
	    $msg .= "  $wahl: Anzahl der Enthaltungen bei den\n".
		"    Listenstimmen nicht definiert\n" ;
	    next ;
	}
	if ( ! defined $liste_summe ) {
	    $msg .= "  $wahl: Summe der Listenstimmen nicht definiert\n" ;
	    next ;
	}
	if ( $gueltig != $liste_summe + $liste_enth ) {
	    $msg .= "  $wahl: Gueltige Stimmen: $gueltig\n".
		"    Summe Listenstimmen + Enthaltungen: ".
		($liste_summe + $liste_enth)."\n" ;
	}
    }
    
    $qry = $dbh->prepare
    ( "SELECT wahl.name_kurz, wahl.max_stimmen_wert, ".
      "wahl_urne.stimmzettel, wahl_urne.stimmzettel_ungueltig, ".
      "wahl_urne.kandidaten_ungueltig, wahl_urne.kandidaten_enthaltungen, ".
      "sum(kandidat_urne.stimmen) ".
      "FROM wahl, liste, kandidat, wahl_urne, kandidat_urne ".
      "WHERE liste.wahl = wahl.id AND kandidat.liste = liste.id ".
      "AND wahl_urne.wahl = wahl.id AND kandidat_urne.kandidat = kandidat.id ".
      "AND kandidat_urne.urne = wahl_urne.urne AND wahl_urne.urne=$urne_id ".
      "GROUP BY wahl.id" ) ;
    $qry->execute;
    while ( @r = $qry->fetchrow_array ) {
	my ( $wahl, $max_stimmen, 
	     $zettel, $zettel_ungueltig,
	     $kand_ungueltig, $kand_enth, $kand_summe ) = @r ;
	if ( ! defined $max_stimmen ) {
	    $msg .= "  $wahl: Wahlen noch nicht ausgewertet\n" ;
	    next ;
	}
	if ( ! defined $zettel ) {
	    $msg .= "  $wahl: Anzahl der Stimmzettel nicht definiert\n" ;
	    next ;
	}
	if ( ! defined $zettel_ungueltig ) {
	    $msg .= "  $wahl: Anzahl der ungueltigen Stimmzettel ".
		"nicht definiert\n" ;
	    next ;
	}
	if ( ! defined $kand_ungueltig ) {
	    $msg .= "  $wahl: Anzahl der ungueltigen Kandidatenstimmen ".
		"nicht definiert\n" ;
	    next ;
	}
	if ( ! defined $kand_summe ) {
	    $msg .= "  $wahl: Summe der Kandidatenstimmen nicht definiert\n" ;
	    next ;
	}
	my ( $ungueltig ) = ($zettel_ungueltig + $kand_ungueltig) ;
	if ( $ungueltig > $zettel ) {
	    $msg .= "  $wahl: Mehr ung�ltige Stimmen ($ungueltig) ".
		"als Stimmzettel ($zettel)\n" ;
	}
	my ( $gueltig ) = ($zettel - $ungueltig) ;
	if ( $max_stimmen == 1 ) {
	    if ( ! defined $kand_enth ) {
		$msg .= "  $wahl: Anzahl der Enthaltungen bei den\n".
		    "    Kandidatenstimmen nicht definiert\n" ;
		next ;
	    }
	    if ( $gueltig != $kand_summe + $kand_enth ) {
		$msg .= "  $wahl: G�ltige Stimmen: $gueltig\n".
		    "    Summe Kandidatenstimmen + Enthaltungen: ".
		    ( $kand_summe + $kand_enth )."\n" ;
	    }
	} else {
	    my ( $max_summe ) = ( $gueltig * $max_stimmen ) ;
	    if ( $kand_summe > $max_summe ) {
		$msg .= "  $wahl: Anzahl der g�ltigen Stimmzettel: $gueltig, ".
		    "Stimmen: $max_stimmen\n".
		    "    maximale Summe Kandidatenstimmen: $max_summe, ".
		    "tats�chlich: $kand_summe\n" ;
	    }
	}
    }
    
    if ( $msg ne "" ) {
	$msg = "Urne $fak $num\n$msg\n" ;
    }
    return $msg ;
}

sub UrnePruefenAlle {
    my ( $dbh ) = @_ ;
    my $msg = "" ;
    my $qry = $dbh->prepare("SELECT id FROM urne");
    $qry->execute;
    while ( my($id) = $qry->fetchrow_array ) {
	$msg .= UrnePruefen ( $dbh, $id ) ;
    }
    return $msg ;
}

sub use_var {}

1 ;
