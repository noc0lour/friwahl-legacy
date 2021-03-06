-- Datenbank fuer elektronisches Waehlerverzeichnis FriCardWahl.
-- 
-- (c) 2002-2004 Christoph Moench-Tegeder <moench-tegeder@rz.uni-karlsruhe.de>
--               Peter Schlaile <Peter.Schlaile@stud.uni-karlsruhe.de>
--               Kristof Koehler <Kristof.Koehler@stud.uni-karlsruhe.de>
-- (c) 2007-2008 Sebastian Maisch <s_maisch@usta.de>
-- (c) 2010-2011 Mario Prausa <mariop@usta.de>
--
-- SVN: $Id: FriCardWahl.sql 403 2011-01-09 19:26:10Z mariop $
--
-- Published under GPL.
--

-- Laufende Nummern fuer die Logtabelle
create sequence seq_log start 1;

grant select, update on seq_log to group g_urnen;
grant select, update on seq_log to group g_ausschuss;


-- Record-Nummer fuer die Statistik
create sequence seq_statistik start 1;

grant select, update on seq_statistik to group g_urnen;
grant select, update on seq_statistik to group g_ausschuss;


-- Laufende Nummern fuer die Queue
create sequence seq_queue start 1;

grant select, update on seq_queue to group g_urnen;
grant select, update on seq_queue to group g_ausschuss;


-- Tabelle fuer die Wahlberechtigten (Plan A) oder WaehlerInnen (Plan B)
-- waehler_matr haelt die Matrikelnummer
-- waehler_buchst haelt zwei Buchstaben des Namens (derzeit geplant:
--   erster Buchstabe des Vornamens und letzter Buchstabe des Nachnamens
-- waehler_client wird benutzt, um die IP-Adresse der gerade aktiven
--   Urne an das Log durchzureichen und um eine Marke fuer ungueltige
--   Zeilen setzen zu koennen. Im Normalbetrieb scheint diese Zelle immer
--   leer.
-- Die meisten Zugriffe auf diese Tabelle laufen ueber waehler_matr.
-- Da jede Matrikelnummer eine Person eindeutig bezeichnet, kann
-- waehler_matr als Primary Key benutzt werden.
create table t_waehler (
	waehler_matr		integer,
	waehler_buchst		char(2),
	waehler_client		inet,
	primary key		(waehler_matr)
	);

grant select, insert, update, delete on t_waehler to group g_urnen;
grant select, insert, update, delete on t_waehler to group g_ausschuss;


-- Tabelle fuer die Zuordnung Code <-> Bezeichnung der Wahl. Wird beim
-- Verbindungsaufbau dem Client angezeigt.
-- Diese Tabelle wird auch benutzt, um festzustellen, welche Wahlen derzeit
-- anstehen.
-- wahl_nr haelt die (interne) Nummer der Wahl, wahl_name die lesbare
-- Bezeichnung.
create table t_wahlen (
	wahl_nr		integer,
	wahl_name	text,
	primary key	(wahl_nr)
	);


grant select on t_wahlen to group g_urnen;
grant select, insert, update, delete on t_wahlen to group g_ausschuss;



-- Tabelle fuer die Waehlerqueues (pro Urne gefuehrt)
-- queue_no laufende Nummer
-- queue_urne Bezeichnung der Urne, zu der das Element gehoert
-- queue_matr Matrikelnummer
-- queue_buchst zusaetzliche Buchstaben aus Waehler-ID
create table t_queue (
	queue_no		integer,
	queue_urne		text,
	queue_matr		integer,
	queue_buchst		char(2),
	primary key		(queue_no)
	);

grant select, insert, update, delete on t_queue to group g_urnen;
grant select, insert, update, delete on t_queue to group g_ausschuss;


-- Elemente der Waehlerqueues (Wahlen pro Waehler)
-- wait_no Laufende Nummer aus t_queue
-- wait_wahl Kennung der Wahl
create table t_waiting (
	wait_no		integer,
	wait_wahl	integer,
	foreign key (wait_no) references t_queue (queue_no) on delete cascade,
	foreign key (wait_wahl) references t_wahlen (wahl_nr)
	);

grant select, insert, update, delete on t_waiting to group g_urnen;
grant select, insert, update, delete on t_waiting to group g_ausschuss;


-- Hier werden Matrikel-Nummer, Buchstaben und Wahlnummern fuer die
-- Queue zusammengefuehrt.
create view v_queue as
	select x.queue_matr as vqueue_matr, x.queue_buchst as vqueue_buchst,
	y.wait_wahl as vqueue_wahl from t_queue as x, t_waiting as y
	where x.queue_no=y.wait_no and x.queue_urne=current_user;

grant select, insert, update, delete on v_queue to group g_urnen;
grant select, insert, update, delete on v_queue to group g_ausschuss;

-- Diese Tabelle loest auf, welcher Waehler welche Stimme abgegeben hat.
-- hat_matr haelt die matrikelnummer des Waehlenden, hat_wahl die
-- Wahlnummer zu der abgegebenen Stimme.
-- Alle Matrikelnummern, die hier eingetragen werden, muessen bereits in
-- t_waehler vorhanden sein. Wird die Matrikelnummer aus t_waehler geloescht,
-- verschwindet sie auch hier.
-- hat_wahl kann nur mit Werten belegt werden, die als wahl_nr in t_wahlen
-- vorhanden sind.
create table t_hat (
	hat_matr	integer,
	hat_wahl	integer,
	foreign key (hat_matr) references t_waehler (waehler_matr) on delete cascade,
	foreign key (hat_wahl) references t_wahlen (wahl_nr)
	);

grant select, insert, update, delete on t_hat to group g_urnen;
grant select, insert, update, delete on t_hat to group g_ausschuss;


-- (Fast) alle Zugriffe auf t_hat laeufen ueber die Matrikelnummern. Da jedes
-- Tupel Matrikelnummer/Wahl eine Zeile benoetigt, ist die Matrikelnummer
-- hier nicht unique, somit wird der Index explizit angelegt (nicht als
-- Primary Key)
create index idx_hat_matr on t_hat (hat_matr);


-- Dieser View erleichtert die Arbeit im Admin-Frontend erheblich.
-- Die Wahlnummern in t_hat werden zu den Wahl-Namen in t_wahlen uebersetzt.
create view v_hat as select x.hat_matr as vhat_matr, y.wahl_name as vhat_wahl,
	y.wahl_nr as vhat_nr
	from t_hat as x, t_wahlen as y where y.wahl_nr=x.hat_wahl;

grant select on v_hat to group g_urnen;
grant select on v_hat to group g_ausschuss;


-- Merker fuer das gerade benutzte Verfahren:
-- A: Daten von der Verwaltung sind vorhanden
-- B: die Datenbank wird bei den Wahlen aufgebaut
-- I: Init-Modus, Urnen werden registriert
create table t_plan (
	plan	char(1)
	);

grant select on t_plan to group g_urnen;
grant select, insert, update, delete on t_plan to group g_ausschuss;


-- Das Log. Hier werden alle Vorgaenge protokolliert.
-- log_nr: laufende Nummer, wird per Trigger gesetzt
-- log_date: Zeitpunkt des Eintrags. Wird per Trigger gesetzt
-- log_level: Art des Eintrags, wird ueber die Tabelle t_loglevel aufgeloest
--   Die Verwendung numerischer Werte bringt beim Schreiben des Logs einen
--   gewissen Performance-Vorteil (INTEGER sind schneller zu parsen als
--   VARCHARs).
-- log_text: der eigentliche Eintrag
-- log_client: IP-Adresse der aktiven Urne
-- log_urne: Username der Urne
-- log_matr: Matrikelnummer des Waehlenden oder 0, wenn der protokollierte
--   Vorgang nicht einer Matrikelnummer in Zusammenhang steht (Sessions
--   sind das offensichtlichste Beispiel)
-- log_buchst: die Buchstaben aus der Waehler-ID oder NULL, wenn keine
--   Waehler-ID gegeben ist
create table t_log (
	log_nr			integer,
	log_date		timestamp,
	log_level		integer,
	log_text		text,
	log_client		inet,
	log_urne		text,
	log_matr		integer,
	log_buchst		char(2)
	);

grant select, insert, update, delete on t_log to group g_urnen;
grant select, insert, update, delete on t_log to group g_ausschuss;


-- Die Zuordnungs der Loglevel-Nummern aus t_log zu den lesbaren Namen.
-- lev_nr: Loglevel, numerisch
-- lev_name: Loglevel, Text
create table t_loglevel (
	lev_nr			integer,
	lev_name		text,
	primary key		(lev_nr)
	);

grant select on t_loglevel to group g_urnen;
grant select on t_loglevel to group g_ausschuss;


-- Dieser View fuehrt die Logtabelle t_log mit den lesbaren Loglevel-
-- Bezeichnungen aus t_loglevel zusammen.
create view v_log as
	select x.log_nr as vlog_nr, y.lev_name as vlog_lev,
		date_trunc('second', x.log_date) as vlog_date, x.log_text as vlog_text,
		x.log_client as vlog_client, x.log_urne as vlog_urne,
		x.log_matr as vlog_matr, x.log_buchst as vlog_buchst
		from t_log as x, t_loglevel as y where x.log_level=y.lev_nr
		order by vlog_nr;

grant select on v_log to group g_urnen;
grant select on v_log to group g_ausschuss;


-- Die Liste der gerade mit der Datenbank verbundenen Clients, sowohl
-- Urnenbezeichnungen als auch IPs. Zusaetzlich wird der Einlogg-Zeitpunkt
-- festgehalten. Nach dem Ende der Session wird der Eintrag aus dieser
-- Tabelle wieder geloescht.
-- client_urne: Username der Urne
-- client_ip: IP-Adresse der Urne
-- client_start: Login-Zeitpunkt
create table t_clients (
	client_urne		text,
	client_ip		inet,
	client_pid		integer,
	client_start		timestamp,
	primary key		(client_urne)
	);

grant select, insert, update, delete on t_clients to group g_urnen;
grant select, insert, update, delete on t_clients to group g_ausschuss;


-- Uebersicht ueber die Urnen. Nur Urnen, die in dieser Tabelle stehen,
-- koennen am Wahlgeschehen teilnehmen.
-- urne_name: Name der Urne
-- urne_inhalt: Anzahl der Stimmzettel, die sich in der Urne befinden
-- urne_gemeldet: Die Urne hat sich am Server angemeldet und ihren Key
--   hinterlegt.
-- urne_broken: Wird dieses Flag gesetzt, geht die Urne ausser Betrieb
-- urne_wer: An wen wurde diese Urne ausgegeben (FS XY, Mensaurne, ...)
create table t_urnen (
	urne_name		text,
	urne_inhalt		integer,
	urne_gemeldet	boolean,
	urne_broken		boolean,
	urne_wer		text,
	primary key		(urne_name)
	);
	
grant select, insert, update on t_urnen to group g_urnen;
grant select, insert, update, delete on t_urnen to group g_ausschuss;


-- Urnenoeffnung und Urnenschluss, ergibt zusammen die Oeffnungszeiten
-- Werden die Urnen ueber Nacht geschlossen, einfach mehrere Paare definieren
create table t_zeiten (
	zeit_anfang		timestamp,
	zeit_ende		timestamp
	);

grant select on t_zeiten to group g_urnen;
grant select, insert, update, delete on t_zeiten to group g_ausschuss;


-- Mit dieser Tabelle lassen sich die Grafiken "Wahlbeteiligung ueber Zeit"
-- und "Waehler pro Zeiteinheit" erzeugen
-- stat_nr: Laufende Nummer des Tupels
-- stat_time: Zeitpunkt der Aufnahme
-- stat_total: Anzahl der Waehler bis zum gegebenen Zeitpunkt
-- stat_delta: Differenz zum vorherigen Eintrag
create table t_statistik (
	stat_nr			integer,
	stat_time		timestamp,
	stat_total		integer,
	stat_delta		integer
	);

grant select, insert, update on t_statistik to group g_urnen;
grant select, insert, update on t_statistik to group g_ausschuss;


-- Fehlermeldungen und Nummern
-- fehler_nr Fehlernummer
-- fehler_text Beschreibung
create table t_fehler (
	fehler_nr		integer,
	fehler_text		text,
	primary key		(fehler_nr)
	);

grant select on t_fehler to group g_urnen;
grant select, insert, update, delete on t_fehler to group g_ausschuss;

-- Diese Tabelle speichert genau ein Textfeld. Dadurch laesst sich auch
-- im laufenden Betrieb sdie Version der Datenbank einfach abfragen.
create table t_version (
	version		text
	);

grant select on t_version to group g_urnen;
grant select, insert, update, delete on t_version to group g_ausschuss;

-- Diese Tabelle enth�lt alle g�ltigen Bibliotheksnummern. Dadurch k�nnen 
-- wir anhand der FriCard feststellen ob der W�hle immatrikuliert ist oder 
-- nicht.
create table t_bibnummern (
	bib_nummer		bigint,
	primary key		(bib_nummer)
	);

grant select on t_bibnummern to group g_urnen;
grant select, insert, update, delete on t_bibnummern to group g_ausschuss;
	
-- Teste ob W�hler mit Bibliotheksnummer w�hlen darf
-- Parameter:
--   $1: bigint Bibliotheksnummer
-- Rueckgabewert:
--   boolean, true: darf w�hlen, false: darf nicht w�hlen
create or replace function checkBibNr(bigint) returns boolean as '
declare
	bibnr		alias for $1;

	foundNr		bigint;

begin
	select into foundNr bib_nummer from t_bibnummern where bib_nummer=bibnr;
	
	if not found then
		return ''false'';
	end if;
	
	return ''true'';
end;'
	language 'plpgsql' with (iscachable);
	

-- Loesche alle Bibliotheksnummern damit die Tabelle bei Veraenderungen
-- neu gefuellt werden kann.
-- Parameter:
--   keine
-- Rueckgabewert:
--   boolean
create or replace function clearbibnummern() returns boolean as '
begin
	delete from t_bibnummern;
	-- 0 einfuegen, da 0 immer akzeptiert wird aber ungueltig ist.
	insert into t_bibnummern (bib_nummer) values (0);

  return ''true'';
end;'
	language 'plpgsql';


-- Fehlernummer zu Text finden
-- Parameter:
--   $1: text	Fehlermeldung
-- Rueckgabewert:
--   integer, Fehlernummer
create or replace function geterror(text) returns text as '
declare
	err		alias for $1;

	n		integer;
	s		text;

begin
	select into n fehler_nr from t_fehler where fehler_text=err;

	if not found then
		n=65535;
	end if;

	s:=''-'' || n::text || ''  '' || err;

	return s;
end;'
	language 'plpgsql' with (iscachable);


-- Diese Funktion erleichtert das Schreiben des Logs.
-- Die Urnen-IP wird aus t_clients gezogen.
-- Parameter:
--   $1: text    Text des Logeintrages
--   $2: integer Loglevel (numerisch)
--   $3: integer Matrikelnummer (wenn sinnvoll)
--   $4: char(2) Buchstaben aus der Waehler-ID (wenn sinnvoll)
-- Rueckgabewert:
--   Bool, immer true
create or replace function logger(text, integer, integer, char(2)) returns boolean as '
declare
	txt		alias for $1;
	lev		alias for $2;
	matr	alias for $3;
	buchst	alias for $4;

	ssh		inet;

begin
	select into ssh client_ip from t_clients where client_urne=current_user;
	if not found then
		ssh:=''0.0.0.0'';
	end if;
	
	insert into t_log (log_client, log_text, log_level, log_matr, log_buchst)
		values (ssh, txt, lev, matr, buchst);
	return ''true'';
end;'
	language 'plpgsql';


-- Diese Funktion erleichtert das Schreiben des Logs.
-- Die Urnen-IP wird als Parameter bezogen (sinnvoll z.B. beim Sessionmanagement
-- Parameter:
--   $1: text    Text des Logeintrages
--   $2: integer Loglevel (numerisch)
--   $3: integer Matrikelnummer (wenn sinnvoll)
--   $4: char(2) Buchstaben aus der Waehler-ID (wenn sinnvoll)
--   $5: inet    IP-Adresse der Urne
-- Rueckgabewert:
--   Bool, immer true
create or replace function logger(text, integer, integer, char(2), inet) returns boolean as '
declare
	txt		alias for $1;
	lev		alias for $2;
	matr	alias for $3;
	buchst	alias for $4;
	ssh		alias for $5;

begin
	insert into t_log (log_client, log_text, log_level, log_matr, log_buchst)
		values (ssh, txt, lev, matr, buchst);
	return ''true'';
end;'
	language 'plpgsql';


-- Login- und Logout-Vorgaenge pruefen und ggf. erfassen.
-- Beim Login wird geprueft, ob die Urne schon eingeloggt ist oder die
-- IP-Adresse der Urne schon von einer anderen Urne benutzt wird.
-- Wenn nicht, wird die Urne in t_clients eingetragen.
-- Beim Logout wird die Urne aus t_clients geloescht. Bei beiden Vorgaengen
-- wird Log gefuehrt.
-- Hier wird die logger()-Variante mit dem zusaetzlichen Parameter ssh
-- benutzt, da hier nicht sichergestellt ist, dass die Session bereits
-- registriert ist (kann sie z.T. gar nicht, Beispiel Doppel-Login)
-- Der Username wird aus current_user gewonnen.
-- Parameter:
--   $1: integer 1 fuer Session-Beginn, 2 fuer Session-Ende
--   $2: inet    IP-Adresse der Urne
--   $3: pid	 PID of clearing.pl 
-- Rueckgabewert:
--   integer, 0 wenn Login erlaubt, -1, wenn nicht, bzw. PID wenn Urne bereits eingeloggt
create or replace function sessionmgmt(integer, inet, integer) returns integer as '
declare
	soe			alias for $1;
	ssh			alias for $2;
	pid			alias for $3;

	os			timestamp;
	p			integer;
	w			boolean;

begin
	if soe=1 then
		-- Zuerst: darf diese Urne ueberhaupt?
		select into w urne_broken from t_urnen
			where urne_name=current_user and not urne_broken;
		if not found then
			w:=logger(''Urne darf nicht benutzt werden'', 2, 0, '''', ssh);
			return -1;
		end if;

		-- Pruefen, ob der Client bereits eingeloggt ist (Tabelle t_clients)
		select into p client_pid from t_clients where client_urne=current_user;
		if found then
			-- Bereits da, ablehnen
			w:=logger(''Bereits eingeloggt'', 2, 0, '''', ssh);
			return p;
		end if;

		-- Versucht ein Client, sich mit mehreren IDs anzumelden?
		select into os client_start from t_clients where client_ip=ssh;
		if found then
			-- Schon gehabt, ablehnen
			w:=logger(''Mehrere Clients auf einer IP'', 2, 0, '''', ssh);
			return -1;
		end if;

		-- noch nicht eingeloggt, annehmen
		w:=logger(''Start'', 2, 0, '''', ssh);
		insert into t_clients (client_urne, client_ip, client_pid, client_start) values (current_user, ssh, pid, ''now'');
		return 0;
	end if;

	if soe=2 then
		delete from t_clients where client_urne=current_user;
		w:=logger(''Ende'', 2, 0, '''', ssh);
	end if;

	return 0;
end;'
	language 'plpgsql';


-- Berechnung der Pruefziffer uebernommen aus
-- http://www.aifb.uni-karlsruhe.de/Lehrangebot/Sommer1999/KommProg/Blatt/p1.ps.gz
-- Kurz: Es sei eine Matrikelnummer z1,z2,z3,z4,z5,z6,z7. z7 ist die
-- Pruefziffer. Gerechnet wird:
-- e = z1*2 + z2 + z3*4 + z4*3 + z5*2 + z6 ; z7 == e%10
-- Einige alte Matrikelnummern passen nicht in das Schema (Info von
-- Herrn Sievers im FriCard-Treffen). Alle Matrikelnummern unter 100000
-- werden grundsaetzlich als gueltig angenommen.
-- Parameter:
--   $1: integer Matrikelnummer
-- Rueckgabewert:
--   Bool, true, wenn Matrikelnummer ok, false, wenn nicht
create or replace function checkMatrikel(integer) returns boolean as '
declare
	matr		alias for $1;

	pz			integer;
	mk			integer;
	t			integer;

begin
	-- Es gibt tatsaechlich noch Leute mit ganz kurzen Matrikelnummern,
	-- die nicht auf das Pruefziffernschema passen. Derzeitige Behandlung:
	-- Eine fuenfstellige Matrikelnummer kann nur echt sein. Wenn ein
	-- Wahlhelfer Ziffern weglaesst, kann eine Matrikelnummer
	-- faelschlicherweise als richtig angenommen werden.
	if matr<100000 then
		return ''true'';
	end if;

	pz:=matr%10;
	mk:=(matr-pz)/10;

	t:=(mk%10);
	mk:=mk/10;
	t:=t+(mk%10)*2;
	mk:=mk/10;
	t:=t+(mk%10)*3;
	mk:=mk/10;
	t:=t+(mk%10)*4;
	mk:=mk/10;
	t:=t+(mk%10);
	mk:=mk/10;
	t:=t+(mk%10)*2;
	
	if t%10=pz then
		return ''true'';
	end if;

	return ''false'';
end;'
	language 'plpgsql' with (iscachable);


-- Hier wird geprueft, ob die gewueschten Wahlen heute wirklich stattfinden
-- Wenn Wahlen kommen, die nicht in t_wahlen stehen, stinkt das nach
-- Manipulation.
-- Parameter:
--   $1 integer   Queue-Kennung fuer t_queue/t_waiting
-- Rueckgabewert:
--   Bool, true, wenn Wahl-Kombination ok, false sonst
create or replace function checkWahlen(integer) returns boolean as '
declare
	wahlen		alias for $1;

	i			integer;
	w			integer;
	r			t_waiting%rowtype;

begin
	i:=1;
	for r in select * from t_waiting where wait_no=wahlen loop
		select into w wahl_nr from t_wahlen where wahl_nr=r.wait_wahl;
		if not found then
			return ''false'';
		end if;
		i:=i+1;
	end loop;

	return ''true'';
end;'
	language 'plpgsql' with (iscachable);


-- Prueft, ob Urne in Betrieb sein darf (nicht gesperrt ist)
-- Parameter:
--   keine
-- Rueckgabewert:
--  boolean, true, wenn Urne ok ist
create or replace function check_urne_ok() returns boolean as '
declare
	r		boolean;
	w		boolean;
	ssh		inet;

begin
	-- Die IP-Adresse der Urne bekommen wir aus t_clients
	-- Damit sind wir auch die Sorge um gesperrte Urnen los, denn
	-- gesperrte Urnen bekomen keine Session.
	select into ssh client_ip from t_clients where client_urne=current_user;
	-- Wenn nicht, ist die Urne nicht eingeloggt, also zurueck
	if not found then
		w:=logger(''Urne nicht eingeloggt und waehlt'', 4, 0, '''');
		return ''false'';
	end if;
	
	-- Urne als defekt markiert? Dann ist sie eben nicht ok...
	select into r urne_broken from t_urnen where urne_name=current_user;
	if r then
		w:=logger(''Kompromittierte Urne waehlt'', 4, 0, '''');
		return ''false'';
	end if;

	-- Darf jetzt gewaehlt werden?
	w:=urnenOffen();
	if not w then
		w:=logger(''Wahlversuch ausserhalb der Urnenzeiten'', 4, 0, '''');
		return ''false'';
	end if;

	return ''true'';
end;'
	language 'plpgsql';


-- Einfuegen eines Waehlers in die Queue
-- Parameter:
--   $1 integer         Matrikelnummer
--   $2 char(2)         Buchstaben aus der Waehler-ID
--   $3 bigint	        Bibliotheksnummer zum Wahlberechtigungstest, 0 ist immer berechtigt 
--			   (d.h. Wahlberechtigung wurde von Wahlhelfern Beispielsweise durch Imma geprueft).
--   $4 integer[]       gewuenschte Wahlen, eine Nr. pro Array-Feld
-- Rueckgabewert:
--  Text, die Meldung, die an den Client zurueckgeliefert wird
create or replace function queue_add(integer, char(2), bigint, integer[]) returns text as '
declare
	matr alias for $1;
	buchst alias for $2;
	bibnr alias for $3;
	wahlen alias for $4;

	r boolean;
	w boolean;
	i integer;
	n integer;
	tlog text;
	err text;
	ssh inet;

begin
	-- Check, ob die Urne generell und speziell jetzt waehlen lassen darf,
	-- wenn das nicht der Fall ist, brauchen wir gar nicht weitermachen.
	r:=check_urne_ok();
	if not r then
		err:=geterror(''Urne darf nicht waehlen'');
		return err;
	end if;

	select into n queue_no from t_queue where
		queue_urne=current_user and queue_matr=matr;
	if found then
		err:=geterror(''Waehler schon in der Schlange'');
		return err;
	end if;
	
	-- Bibliotheksnummer pruefen um Wahlberechtigung festzustellen.
	w:=checkBibNr(bibnr);
	if not w then
		w:=logger(''Ungueltige Bibliotheksnummer'', 3, matr, buchst);
		err:=geterror(''Waehler nicht berechtigt oder Bibliotheksnummer falsch'');
		return err;
	end if;
	
	-- Zuerst den Waehler als solchen in die Schlange stellen
	-- "Bitte Nummer ziehen!"
	insert into t_queue (queue_matr, queue_buchst, queue_urne)
		values(matr, buchst, current_user);

	-- Wenn er nichts waehlen will, soll uns das recht sein, das macht die
	-- Sache nur einfacher
	if wahlen[1] is null then
		w:=logger(''Leere Transaktion'', 3, matr, buchst);
		return ''+OK'';
	end if;

	-- Welche Nummer?
	select into n queue_no from t_queue where
		queue_urne=current_user and queue_matr=matr;

	-- Und jetzt die Details, eins nach dem anderen
	i:=1;
	while wahlen[i] is not null loop
		insert into t_waiting (wait_no, wait_wahl) values (n, wahlen[i]);
		i:=i+1;
	end loop;

	-- Fertig
	return ''+OK'';
end;'
	language 'plpgsql';

-- Loeschen eines Queue-Eintrages.
-- Parameter:
--   matr	integer	Matrikelnummer
--   buchst	char(2)	Buchstaben dazu
-- Rueckgabewert:
--   text, OK (oder die Datenbank wirft Fehler)
create or replace function queue_remove(integer, char(2)) returns text as '
declare
	matr	alias for $1;
	buchst	alias for $2;

begin
	-- Ganz einfach: Aus t_queue verschwinden lassen, den Rest macht die
	-- Referenz von t_waiting. Und wenn die Datenbank nicht noergelt
	-- ist der Waehler auch wirklich raus.
	delete from t_queue where
		queue_matr=matr and queue_buchst=buchst and queue_urne=current_user;

	return ''+OK'';
end;'
	language 'plpgsql';


-- Das eigentliche Kernstueck des ganzen Verfahrens. Die Waehler-ID wird
-- geprueft, ggf. die Eintrqagungen in der Datenbank vorgenommen und auf
-- jeden Fall das Log geschrieben.
-- Die abschickende Urne muss den Waehler (und damit auch seine Wahlen)
-- vorher in die Queue gestellt haben, sonst stimmt da was nicht.
-- Der Username der Urne wird aus current_user genommen.
-- Unschoen: Nach dem Aufruf von waehlt muss die Waehler-ID aus der
-- Queue verschwunden sein. Da nicht zwingendermassen ein Eintrag in
-- t_hat oder t_waehler stattfindet, muss die Queue an jedem return
-- geraeumt werden.
-- Parameter:
--   $1 integer         Matrikelnummer
--   $2 char(2)         Buchstaben aus der Waehler-ID
--   $3 integer[]       tatsächlich gewählte Wahlen (nur bei elektronischer Wahl, sonst keine Bedeutung)
-- Rueckgabewert:
--  Text, die Meldung, die an den Client zurueckgeliefert wird
create or replace function waehlt(integer, char(2), integer[]) returns text as '
declare
	matr alias for $1;
	buchst alias for $2;
  gewaehlt alias for $3;

	w boolean;
	t integer;
	i integer;
  j   integer;
	n integer;
	nwahlen integer;
        nwahlenel integer;
	tmatr integer;
	wahlen integer;
  wahl integer;
        wahlnum integer;
	p char(1);
	tb char(2);
	id text;
	tid text;
	tlog text;
	err text;
	tmp text;
	ssh inet;
	r t_hat%rowtype;
	x t_waiting%rowtype;

begin
	-- Check, ob die Urne generell und speziell jetzt waehlen lassen darf,
	-- wenn das nicht der Fall ist, brauchen wir gar nicht weitermachen.
	w:=check_urne_ok();
	if not w then
		tmp:=queue_remove(matr, buchst);
		err:=geterror(''Urne darf nicht waehlen'');
		return err;
	end if;

	-- Wir benoetigen die IP-Adresse der Urne
	select into ssh client_ip from t_clients where client_urne=current_user;

	-- Queue ueberpruefen
	select into wahlen queue_no from t_queue where
		queue_matr=matr and queue_buchst=buchst and queue_urne=current_user;
	if not found then
		tmp:=queue_remove(matr, buchst);
		err:=geterror(''Waehler nicht in der Schlange'');
		return err;
	end if;

	-- Die gewuenschten Wahlen bekommen wir aus der Queue, die Queue-ID
	-- haben wir uns ja schon geholt
	select into nwahlen count(wait_wahl) from t_waiting where wait_no=wahlen;

	tlog:=''Transaktion:'';
	for x in select * from t_waiting where wait_no=wahlen loop
		tlog:=tlog || '' '' || x.wait_wahl;
	end loop;

	-- Zuerst die geplante Transaktion in das Log schreiben
	w:=logger(tlog, 1, matr, buchst);

	-- Bevor wir ueberhaupt irgendwas tun, pruefen wir, ob die Wahlen
	-- ueberhaupt stattfinden
	w:=checkWahlen(wahlen);
	if not w then
		-- Mindestens eine der gewuenschten Wahlen gibt es nicht.
		-- Das riecht nach Manipulation (der Client tut sowas nicht).
		-- Protokollieren und Wahl verweigern.
		w:=logger(''Ungueltige Wahlen'', 3, matr, buchst);
		tmp:=queue_remove(matr, buchst);
		err:=geterror(''Wird nicht gewaehlt'');
		return err;
	end if;

	-- Jetzt nachsehen, nach welchen Plan wir arbeiten
	select into p plan from t_plan limit 1;

	if p=''A'' then
		-- Plan A: Wir haben Daten von der Verwaltung
		-- Achtung: Sollten wir irgendwann nach Plan A arbeiten muss dieser Zweig
		-- wahrscheinlich zum Teil neu geschrieben werden. (Stand 30.12.2007, s_maisch)

		-- Tabellen sperren, damit schliessen wir alle Races einfach aus
		lock t_waehler in exclusive mode;
		lock t_hat in exclusive mode;

		-- Nachsehen, ob Person existiert und gewuenschte Stimmen noch nicht
		-- abgegeben hat.
		select into tb waehler_buchst from t_waehler where waehler_matr=matr;
		if found then
			if not tb=buchst then
				-- Die Nummer ist bekannt, aber mit anderen Buchstaben
				w:=logger(''Buchstaben passen nicht'', 3, matr, buchst);
				tmp:=queue_remove(matr, buchst);
				err:=geterror(''Buchstaben passen nicht zu Matrikel-Nr.'');
				return err;
			end if;
			
			for x in select * from t_waiting where wait_no=wahlen loop
				-- Sobald eine Wahlnummer gefunden wird, die bereits als
				-- abgegeben erfasst wurde, erfolgt Logeintrag und Ruecksprung
				select into r * from t_hat
					where hat_matr=matr and hat_wahl=x.wait_wahl;
				if found then
					w:=logger(''Versuch Mehrfachwahl'', 3, matr, buchst);
					tmp:=queue_remove(matr, buchst);
					err:=geterror(''Stimme schon abgegeben'');
					return err;
				end if;
			end loop;
				
			-- Person existiert und darf waehlen, eintragen und "OK" geben.
			for x in select * from t_waiting where wait_no=wahlen loop
				insert into t_hat (hat_matr, hat_wahl)
					values (matr, x.wait_wahl);
			end loop;
			update t_waehler set waehler_client=ssh where waehler_matr=matr;
			w:=logger(''Positiv'', 1, matr, buchst);
			t:=updateInhalt(nwahlen);
			tmp:=queue_remove(matr, buchst);
			return ''+OK'';
		else
			-- Person existiert nicht. Vorfall protokollieren und Wahl ablehnen.
			w:=logger(''Waehler-ID unbekannt'', 3, matr, buchst);
			tmp:=queue_remove(matr, buchst);
			err:=geterror(''Waehler-ID unbekannt'');
			return err;
		end if;
	elsif p=''B'' then
		-- Plan B, wir bauen die Datenbank auf

		-- Matrikelnummer pruefen, ob Pruefziffer stimmt.
		-- Protokollieren und Wahl verweigern, wenn nicht.
		w:=checkMatrikel(matr);
		if not w then
			w:=logger(''Pruefsummenfehler'', 3, matr, buchst);
			tmp:=queue_remove(matr, buchst);
			err:=geterror(''keine Matrikelnummer'');
			return err;
		end if;

		-- Die Matrikelnummer scheint gueltig, also machen wir weiter.

		-- Waehler scheint wahlberechtigt, also machen wir weiter.
		-- Vorher setzen wir aber einen Lock auf die Tabellen, dann gibt es
		-- sicher keine Races.
		lock t_waehler in exclusive mode;
		lock t_hat in exclusive mode;

		-- Kennen wir diese Person?
		select into tb waehler_buchst from t_waehler where waehler_matr=matr;
		if not found then
			-- Matrikelnummer noch nicht registriert, also auf jeden
			-- Fall wahlberechtigt. Eintragen und "OK".
			insert into t_waehler (waehler_matr, waehler_buchst, waehler_client)
				values (matr, buchst, ssh);

			for x in select * from t_waiting where wait_no=wahlen loop
	   			insert into t_hat (hat_matr, hat_wahl)
			   		values (matr, x.wait_wahl);
			end loop;

			w:=logger(''Positiv'', 1, matr, buchst);
			tmp:=queue_remove(matr, buchst);
			t:=updateInhalt(nwahlen);
			return ''+OK'';
		else
			-- Die Matrikelnummer ist bekannt, aber mit anderen Buchstaben
			if not tb=buchst then
				w:=logger(''Buchstaben falsch'', 3, matr, buchst);
				tmp:=queue_remove(matr, buchst);
				err:=geterror(''Buchstaben passen nicht zu Matrikel-Nr.'');
				return err;
			end if;
			-- Bereits registriert, also vermutlich verteilte Wahl.
			-- Wir pruefen bereits Gewaehltes.
			
        		-- alle Wahlen der Datenbank pruefen und setzen
			  for x in select * from t_waiting where wait_no=wahlen loop
				  select into r * from t_hat
					  where hat_matr=matr and hat_wahl=x.wait_wahl;
				  if found then
					  w:=logger(''Versuch Mehrfachwahl'', 3, matr, buchst);
					  tmp:=queue_remove(matr, buchst);
					  err:=geterror(''Stimme bereits abgegeben'');
					  return err;
				  end if;
			  end loop;

			  for x in select * from t_waiting where wait_no=wahlen loop
				  insert into t_hat (hat_matr, hat_wahl)
					  values (matr, x.wait_wahl);
			  end loop;

			update t_waehler set waehler_client=ssh where waehler_matr=matr;
			w:=logger(''Positiv'', 1, matr, buchst);
			tmp:=queue_remove(matr, buchst);
			t:=updateInhalt(nwahlen);
			return ''+OK'';
		end if;
	elsif p=''I'' then
		w:=logger(''wahlversuch im Init-Modus'', 4, matr, buchst);
		tmp:=queue_remove(matr, buchst);
		err:=geterror(''Jetzt nicht'');
		return err;
	end if;

	w:=logger(''Falltrough in waehlt()'', 4, matr, buchst);
	tmp:=queue_remove(matr, buchst);
	err:=geterror(''Interner Fehler'');
	return err;
end;'
	language 'plpgsql';


-- Inkrementiert die Anzahl der Stimmzettel in einer Urne
-- Parameter:
--   $1 integer  Anzahl der hinzugekommenen Stimmzettel
-- Rueckgabewert:
--   Integer, Kopie von Parameter $1
create or replace function updateInhalt(integer) returns integer as '
declare
	n	alias for $1;

	t	integer;

begin
	select into t urne_inhalt from t_urnen where urne_name=current_user;
	update t_urnen set urne_inhalt=t+n where urne_name=current_user;

	return n;
end;'
	language 'plpgsql';



-- Stellt fest, ob gerade Urnen geoeffnet sind.
-- Parameter: keine
-- Rueckgabewert:
-- 	 Boolean, ''true'', wenn Urnen geoeffnet sein duerfen
create or replace function urnenOffen() returns boolean as '
declare
	t	timestamp;

begin
	select into t zeit_anfang from t_zeiten
		where current_timestamp between zeit_anfang and zeit_ende;
	if not found then
		return ''false'';
	end if;

	return ''true'';
end;'
	language 'plpgsql';



-- Stellt fest, ob gerade Wahlperiode ist, d.h. ob wir uns zwischen der
-- ersten Urnenoeffnung und dem letzten Urnenschluss befinden.
-- Parameter: keine
-- Rueckgabewert:
--   Integer, -1, wenn vor der Wahlperiode oder nicht definiert,
--     0 waehrend der Wahlperiode, 1 nach der Wahlperiode
create or replace function wahlperiode() returns integer as '
declare
	ta		timestamp;
	te		timestamp;

begin
	select into ta zeit_anfang from t_zeiten order by zeit_anfang limit 1;
	if not found then
		return -1;
	end if;
	if current_timestamp<ta then
		return -1;
	end if;

	select into te zeit_ende from t_zeiten order by zeit_ende desc limit 1;
	if current_timestamp>te then
		return 1;
	end if;

	return 0;
end;'
	language 'plpgsql';



-- Setzt die abgegebenen Stimmen eines Waehlers. Vereinfacht die Arbeit
-- des Admin-Frontends ungemein.
-- Parameter:
--   $1 integer    Matrikelnummer
--   $2 char(2)    Buchstaben aus der Waehler-ID
--   $3 integer[]  Stimmen, die als abgegeben eingetragen werden sollen
-- Rueckgabewert:
--   Boolean, ''true'', wen Aenderung durchgefuert
create or replace function set_waehler_attr(integer, char(2), integer[]) returns boolean as '
declare
	matr	alias for $1;
	buchst	alias for $2;
	wahlen	alias for $3;

	w		boolean;
	m		integer;
	i		integer;
	t		text;

begin
	t:=''Admin setzt Waehler-Attribute:'';
	i:=1;
	while wahlen[i] is not null loop
		t:=t || '' '' || wahlen[i];
		i:=i+1;
	end loop;

	w:=logger(t, 5, matr, buchst);

	select into m hat_matr from t_hat where hat_matr=matr limit 1;
	if not found then
		w:=logger(''Waehler nicht gefunden'', 5, matr, buchst);
		return ''false'';
	end if;

	-- Tabellen sperren, dann kann es keinen Aerger geben
	lock t_hat in exclusive mode;
	delete from t_hat where hat_matr=matr;
	
	i:=1;
	while wahlen[i] is not null loop
		insert into t_hat (hat_matr, hat_wahl) values (matr, wahlen[i]);
		i:=i+1;
	end loop;

	w:=logger(''Operation erfolgreich'', 5, matr, buchst);

	return ''true'';
end;'
	language 'plpgsql';


-- Eintragen der Urnenzeiten und Wahlen, kurz: die Vorbereitung
-- Zur Vereinfachung des Admin-Frontends alles in einer Funktion
-- Parameter:
--   $1 timestamp[]  Die Urnen-Oeffnungszeiten im Array
--   $2 timestamp[]  Die dazugehoerigen Urnenschlusszeiten
--   $3 text[]       Die Wahl-bezeichnungen fuer t_wahlen
-- Rueckgabewert:
--   Boolean, ''true'', wenn alles funktioniert hat
create or replace function vorbereitung(timestamp[], timestamp[], text[]) returns boolean as '
declare
	oeffnet		alias for $1;
	schliesst	alias for $2;
	wahlen		alias for $3;

	i			integer;
	w			boolean;

begin
	i:=1;
	while oeffnet[i] is not null and schliesst[i] is not null loop
		insert into t_zeiten (zeit_anfang, zeit_ende) values
			(oeffnet[i], schliesst[i]);
		i:=i+1;
	end loop;

	i:=1;
	while wahlen[i] is not null loop
		insert into t_wahlen (wahl_nr, wahl_name) values (i, wahlen[i]);
		i:=i+1;
	end loop;

	w:=logger(''Urnenzeiten und Wahlen eingetragen'', 5, 0, '''');

	return ''true'';
end;'
	language 'plpgsql';


-- Anlegen einer neuen Urne, funktioniert nur, wenn Plan I wie Initialisieren
-- gesetzt ist.
-- Parameter:
--   $1 text  Name der Urne
--   $2 text  Betreuer der Urne
-- Rueckgabewert:
--   Boolean, ''true'' wenn Urne erfolgreich angelegt
create or replace function urne_neu(text) returns boolean as '
declare
	wer		alias for $1;

	p		char(1);
	n		integer;
	w		boolean;
	u		text;

begin
	select into p plan from t_plan limit 1;
	if not p=''I'' then
		w:=logger(''Versuch Urne anlegen ohne Plan I'', 4, 0, '''');
		return ''false'';
	end if;

	-- Mit diesem Lock schliessen wir aus, dass uns eine zweite Operation in
	-- die Quere kommt
	lock table t_urnen in exclusive mode;
	select into u urne_name from t_urnen where urne_gemeldet=''false'';
	if found then
		return ''false'';
	end if;

	insert into t_urnen
		(urne_name, urne_inhalt, urne_gemeldet, urne_broken, urne_wer)
		values (''__VORBEREITUNG'', 0, ''false'', ''false'', wer);

	w:=logger(''Urne angelegt'', 5, 0, '''');

	return ''true'';
end;'
	language 'plpgsql';


-- reset_vorb() setzt die "Wahlvorbereitungen" (genauer: Definition der
-- Wahlen und Urnenzeiten) zurueck. Dabei wird geprueft, ob jetzt ein
-- Ruecksetzen erlaubt ist (Plan und Wahlperiode).
-- Log wird mit IP 0.0.0.0 geschrieben -> Administrative Taetigkeit,
-- erfolgt idR an der lokalen Konsole.
-- Parameter: keine
-- Rueckgabewert:
--   boolean, true, wenn Erfolg, false sonst.
create or replace function reset_vorb() returns boolean as '
declare
	w	boolean;
	c	character(1);
	n	integer;	
	t	text;

begin
	select into c plan from t_plan;
	if found then
		t:=''Zuruecksetzen jetzt nicht moeglich'';
		w:=logger(t, 5, 0, '''', ''0.0.0.0'');
		return ''false'';
	end if;

	n:=wahlperiode();
	if not n=-1 then
		t:=''Zuruecksetzen jetzt nicht moeglich'';
		w:=logger(t, 5, 0, '''', ''0.0.0.0'');
		return ''false'';
	end if;

	delete from t_zeiten;
	delete from t_wahlen;
	w:=logger(''Vorbereitung zurueckgesetzt'', 5, 0, '''', ''0.0.0.0'');

	return ''true'';
end;'
	language 'plpgsql';

-- reset_db() setzt die "Datenbank" (genauer: Definition der
-- Wahlen und Urnenzeiten, Waehlerdaten) zurueck. Dabei werden
-- keine Sicherheitsabfragen durchgefuehrt.
-- Log wird mit IP 0.0.0.0 geschrieben -> Administrative Taetigkeit,
-- erfolgt idR an der lokalen Konsole.
-- Parameter: keine
-- Rueckgabewert:
--   boolean, true, wenn Erfolg, false sonst.
create or replace function reset_db() returns boolean as '
declare
	w	boolean;
	c	character(1);
	n	integer;	
	t	text;

begin
	lock t_clients in exclusive mode;

	delete from t_clients;
	delete from t_plan;
	delete from t_urnen;
	delete from t_waiting;
	delete from t_queue;
	delete from t_hat;
	delete from t_waehler;
	delete from t_zeiten;
	delete from t_wahlen;
	delete from t_bibnummern;
	insert into t_bibnummern (bib_nummer) values (0);

	w:=logger(''Datenbank zurueckgesetzt'', 5, 0, '''', ''0.0.0.0'');

	return ''true'';
end;'
	language 'plpgsql';


-- Zum schnellen Nachsehen, wieviele Personen schon mindestens eine
-- Stimme abgegeben haben.
-- Parameter: keine
-- Rueckgabewert:
--   Integer, Anzahl der Personen, die mindestens eine Stimme abgegeben
--            haben
create or replace function gewaehlt() returns integer as '
declare
	n		integer;
	r		record;

begin
	-- Aggregates funktionieren hier leider nicht, also zaehlen wir die
	-- Matrikelnummern per Hand.
	n:=0;
	for r in select distinct on (hat_matr) hat_matr from t_hat loop
		n:=n+1;
	end loop;

	return n;
end;'
	language 'plpgsql';


-- Berechnung der Wahlbeteiligung ausschliesslich aus Daten aus der Datenbank
-- Diese Variante nur fuer Plan A, in Plan B kennen wir die Anzahl der
-- Wahlberechtigten nicht
-- Parameter: keine
-- Rueckgabewert:
--   Float, Wahlbeteiligung (in Teilen von 1) oder -1, wenn Plan B vorliegt
create or replace function Wahlbeteiligung() returns float as '
declare
	w		float;
	p		char(1);

begin
	-- Wir brauchen den Plan, mit Plan B hat diese Funktion keinen Sinn
	-- (die Datenbank weiss nicht, wie viele Leute wahlberechtigt sind)
	select into p plan from t_plan limit 1;
	if p=''B'' then
		return -1.0;
	end if;

	-- Wahlbeteiligung ist Waehler durch Wahlberechtigte
	select into w (gewaehlt()::float)/count(t.waehler_matr) from t_waehler as t;
	return w;
end;'
	language 'plpgsql';


-- Berechnung der Wahlbeteiligung mit externer Angabe der Anzahl der
-- Wahlberechtigten.
-- Wie oben, nur hier kommt die Zahl der Wahlberechtigten von aussen
-- (sinnvoll z.B. bei Plan B (ohne Verwaltungsdaten))
-- Parameter:
--   $1 integer Anzahl der Wahlberechtigen
-- Rueckgabewert:
--   float, Wahlbeteiligung in Teilen von 1
create or replace function Wahlbeteiligung(integer) returns float as '
declare
	g		alias for $1;

	w		float;

begin
	-- Wahlbeteiligung ist Waehler durch Wahlberechtigte
	w:=gewaehlt()/(g::float);
	return w;
end;'
	language 'plpgsql';


-- Triggerfunktion zur Verwendung vor dem Einfuegen oder Updaten der
-- Tabelle. Die Zeile wird auf Plausiblitaet geprueft (Matrikelnummer,
-- korrekte Angabe der Urne etc.).
-- Die Urnen-IP wird geloescht, es sei denn, es werden Unstimmigkeiten
-- gefunden, dann wird 0.0.0.0 gesetzt und Log geschrieben.
-- Im Fall grober Manipulation wird die Transaktion abgebrochen.
create or replace function tg_waehler_func() returns opaque as '
declare
	matr		integer;
	buchst		char(2);
	t		boolean;
	p		char(1);
	client		inet;

begin
	-- Pruefung auf Manipulationen beim Neuanlegen von Waehlern
	-- Nur bei Plan B relevant
	-- Bei Plan A koennen keine Waehler neu angelegt werden

	-- Wenn eine Zeile geloescht wird, dann nur die mit dem markierten
	-- waehler_client-Feld (0.0.0.0)
	-- Transaktionsabbruch ist hier gerechtfertigt
	if TG_OP=''DELETE'' then
		if OLD.waehler_client!=''0.0.0.0'' then
			raise exception ''DELETE hier nicht erlaubt'';
		end if;
		return OLD;
	end if;

	-- Wenn waehler_client nicht gesetzt ist, geht was schief
	if NEW.waehler_client is null then
		t:=logger(''waehler_client nicht gesetzt'', 4, 0, '''');
		-- Nach diesem Kriterium wird im zweiten Trigger aufgeraeumt
		NEW.waehler_client:=''0.0.0.0'';
		-- sofort zurueck, damit die Marke nicht zurueckgesetzt wird
		return NEW;
		end if;

	-- Die Variable soll nacher nicht in der Datenbank stehen, also sichern
	-- wir sie jetzt und loeschen sofort
	client:=NEW.waehler_client;
	NEW.waehler_client:=NULL; 

	-- Erstmal Plan pruefen
	select into p plan from t_plan limit 1;
	if p=''A'' and TG_OP=''INSERT'' then
		t:=logger(''Neuer Waehler in Modus Plan A'', 4, NEW.waehler_matr, NEW.waehler_buchst);
		NEW.waehler_client:=''0.0.0.0'';
		return NEW;
	end if;

	if NEW.waehler_matr=0 then
		-- Matrikelnummer ist 0
		t:=logger(''Defekte ID entdeckt (0)'', 4, 0, '''');
		NEW.waehler_client:=''0.0.0.0'';
		return NEW;
	end if;

	if not checkMatrikel(NEW.waehler_matr) then
		-- Pruefsummenfehler
		t:=logger(''Defekte ID entdeckt (Pruefsumme)'', 4, NEW.waehler_matr, NEW.waehler_buchst);
		NEW.waehler_client:=''0.0.0.0'';
		return NEW;
	end if;

	return NEW;
end;'
	language 'plpgsql';


-- Triggerfunktion zur Verwendung nach Eintragungen in die Tabelle.
-- Alle als falsch markierten Zeilen werden geloescht.
create or replace function tg_waehler_clean() returns opaque as '
begin
	-- Alle Zeilen entsorgen, die vom Trigger vorher als falsch markiert wurden
	delete from t_waehler where waehler_client=''0.0.0.0'';

	return NEW;
end;'
	language 'plpgsql';


-- Triggerfunktion fuer das Log. Vor dem Einfuegen wird der Eintrag mit
-- laufender Nummer, Datum und Urnen-User aufgefuellt.
-- Es werden nur INSERTs zugelassen, alles andere fuehrt zu Abbruch.
create or replace function tg_log_func() returns opaque as '
begin
	if TG_OP != ''INSERT'' then
		-- Am Log wird nur angehaegt, nie ueberschrieben
		raise exception ''Log ist Append-Only'';
	end if;

	-- Setzen von Datum und Sequenznummer im Log
	NEW.log_nr:=nextval(''seq_log'');
	NEW.log_date:=''now'';
	NEW.log_urne:=current_user;
	return NEW;
end;'
	language 'plpgsql';


-- Triggerfunktion fuer die Queue (vor der Aenderung).
-- Funktionen: 
--   DELETE - nur erlauben, wenn selbe Urne
--   UPDATE - geht nicht
--   INSERT - Lfd. Nummer mitfuehren.
create or replace function tg_queue_func() returns opaque as '
begin
	if TG_OP=''DELETE'' then
		if OLD.queue_urne=current_user then
			return OLD;
		else
			raise exception ''Hier nicht loeschen'';
		end if;
	elsif TG_OP=''UPDATE'' then
		raise exception ''Update auf Queue geht nicht'';
	elsif TG_OP=''INSERT'' then
		NEW.queue_no:=nextval(''seq_queue'');
		return NEW;
	end if;

	return NEW;
end;'
	language 'plpgsql';


-- Triggerfunktion fuer die Statistik-Tabelle. Hier werden Delta, Zeitpunkt
-- und laufende Nummer auf jeden neuen Eintrag gesetzt.
create or replace function tg_statistik_func() returns opaque as '
declare
	old			integer;

begin
	-- Delta und Zeitpunkt fuer die Statistik setzen

	-- Alten Total-Wert holen
	select into old stat_total from t_statistik order by stat_nr desc limit 1;

	NEW.stat_delta:=NEW.total-old;
	NEW.stat_date:=''now'';
	NEW.stat_nr:=nextval(''seq_statistik'');

	return NEW;
end;'
	language 'plpgsql';


-- Registriert Urnen an jeglicher Vernunft vorbei in der Datenbank,
-- d.h. traegt einfach Urnenname und Betreuer in die DB ein, setzt
-- gemeldet und fertig ist.
-- Parameter:
--   $1  text   Name der Urne
--   $2  text   Betreuer
-- Rueckgabewert
--   boolean, ''true'', wenn Erfolg, ''false'' sonst
create or replace function register_urne(text, text) returns boolean as '
declare
	urne	alias for $1;
	wer		alias for $2;

	u		text;
	w		boolean;

begin
	-- Keine Races, bitte
	lock t_urnen in exclusive mode;

	-- Ist der Urnen-Name schon vergeben?
	select into u urne_name from t_urnen where urne_name=urne;
	if found then
		w:=logger(''Versuch Doppelregistrierung '' || urne, 5, 0, '''', ''127.0.0.1'');
		return ''false'';
	end if;

	-- Jetzt eintragen
	insert into t_urnen
		(urne_name, urne_inhalt, urne_gemeldet, urne_broken, urne_wer)
		values (urne, 0, ''true'', ''false'', wer);

	w:=logger(''Urnen-Schnell-Registrierung erfolgreich '' || urne, 5, 0, '''', ''127.0.0.1'');

	return ''true'';
end;'
	language 'plpgsql';


-- Eintragen der Triggerfunktionen
create trigger tg_waehler_vor before insert or update or delete on t_waehler
	for each row execute procedure tg_waehler_func();
create trigger tg_waehler_nach after insert or update on t_waehler
	for each row execute procedure tg_waehler_clean();
create trigger tg_queue before insert or update or delete on t_queue
	for each row execute procedure tg_queue_func();
create trigger tg_log_vor before insert or update or delete on t_log
	for each row execute procedure tg_log_func();
create trigger tg_statistik_vor before insert on t_statistik
	for each row execute procedure tg_statistik_func();


-- Fuellen der Tabelle mit den Loglevels, nur der Vollstaendigkeit halber
insert into t_loglevel (lev_nr, lev_name) values (1, 'INFO');
insert into t_loglevel (lev_nr, lev_name) values (2, 'SESSION');
insert into t_loglevel (lev_nr, lev_name) values (3, 'FEHLER');
insert into t_loglevel (lev_nr, lev_name) values (4, 'FATAL');
insert into t_loglevel (lev_nr, lev_name) values (5, 'ADMIN');


-- Fehlertabelle fuellen
insert into t_fehler (fehler_nr, fehler_text)
	values (1, 'Nicht eingeloggt');
insert into t_fehler (fehler_nr, fehler_text)
	values (2, 'Jetzt nicht');
insert into t_fehler (fehler_nr, fehler_text)
	values (3, 'Wird nicht gewaehlt');
insert into t_fehler (fehler_nr, fehler_text)
	values (4, 'Buchstaben passen nicht zu Matrikel-Nr.');
insert into t_fehler (fehler_nr, fehler_text)
	values (5, 'Stimme schon abgegeben');
insert into t_fehler (fehler_nr, fehler_text)
	values (6, 'Waehler-ID unbekannt');
insert into t_fehler (fehler_nr, fehler_text)
	values (7, 'keine Matrikelnummer');
insert into t_fehler (fehler_nr, fehler_text)
	values (8, 'Stimme bereits abgegeben');
insert into t_fehler (fehler_nr, fehler_text)
	values (9, 'Interner Fehler');
insert into t_fehler (fehler_nr, fehler_text)
	values (10, 'Urne gesperrt');
insert into t_fehler (fehler_nr, fehler_text)
	values (11, 'Urne darf nicht waehlen');
insert into t_fehler (fehler_nr, fehler_text)
	values (12, 'Waehler schon in der Schlange');
insert into t_fehler (fehler_nr, fehler_text)
	values (13, 'Waehler nicht in der Schlange');
-- Neu fuer elektronische Wahlen
insert into t_fehler (fehler_nr, fehler_text)
	values (101, 'Waehler hat Karte');
-- Neu fuer Immatrikulationsbestaetigung
insert into t_fehler (fehler_nr, fehler_text)
	values (201, 'Waehler nicht berechtigt');
-- Nur fuer Frontend
insert into t_fehler (fehler_nr, fehler_text)
	values (65533, 'Protokollfehler');
insert into t_fehler (fehler_nr, fehler_text)
	values (65534, 'DB-Fehler, siehe Text');
-- Alles andere
insert into t_fehler (fehler_nr, fehler_text)
	values (65535, 'Sonstiger Fehler');

-- Bibliotheksnummer '0' immer erlauben
insert into t_bibnummern (bib_nummer) values (0);

-- Version speichern
update t_version set version='$Id: FriCardWahl.sql 403 2011-01-09 19:26:10Z mariop $';
