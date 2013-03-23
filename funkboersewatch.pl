use strict;
use warnings;
use LWP 5.64;
use Config::Simple;

#TODO check if config file exists
our $config = new Config::Simple($ENV{HOME}."/.funkboersewatchrc");

our $JABBER_ID      = $config->param(-block=>'jabber')->{id}; 
our $JABBER_PASSWD  = $config->param(-block=>'jabber')->{passwd};
our $JABBER_SERVER  = $config->param(-block=>'jabber')->{server};
our $JABBER_PORT    = $config->param(-block=>'jabber')->{port}; 
our $SEEN_DB_FILE   = $config->param(-block=>'general')->{seen_db_file};
our %SEEN;

use Net::Jabber qw(Client);
use DB_File;
use Log::Log4perl qw(:easy);

Log::Log4perl->easy_init( { level => $DEBUG, 
                           file => ">>/tmp/funkboersewatch.log" } 
);

tie %SEEN, 'DB_File', $SEEN_DB_FILE, 
    O_CREAT|O_RDWR, 0755 or 
    LOGDIE "tie: $SEEN_DB_FILE ($!)";

END { untie %SEEN }

# einen Browser bauen
my $browser = LWP::UserAgent->new();
$browser->timeout(20);
$browser->agent('Mozilla/4.7 [en] (WinNT; I) [Netscape]');

# das ist der link den wir aufrufen wollen
my $link = 'http://www.funkboerse.de/cgi-bin/suche.cgi?seite=1&num=1&auswahl=1&ausrub=2';

# einen request bauen
my $request = HTTP::Request->new('GET',$link);
$request ->header( 'Referer' => 'http://www.google.de');

# die seite holen
my $seite = $browser->request($request); 
my $seite_code = $seite->decoded_content();
#print $seite_code;

# ueber die einzelnen Anzeigen iterieren
while($seite_code =~ m/<table.*?>(.*?)<\/table>/gimosx)
{
	my $line = $1;
	my $typ = "Biete";

	my $temp = $line;
	if($temp =~ m/Suche/g)
	{
	#	next;
		$typ = "Suche";
	}


	#diese zeile matcht keine gewerblichen anzeigen (die interessieren mich nicht)
	if($line =~ m/<tr>.*?\(Anzeigen-Nr.*?(\d*?)\).*?size="-1">(.*?)<\/font/gimosx)
	{
		my $anzeigennummer = $1;
		my $titel = $2;
		$titel =~ s/&nbsp;//g;
		$titel =~ s/[^[:print:]]//g;
		my $message = chr(27)."[0;35;40m$titel".chr(27)."[0;35;40m\nTyp = $typ\nurl = http://www.funkboerse.de/cgi-bin/infomail.cgi?nid=$anzeigennummer&vonwo=0&suche=1\n";
		if($SEEN{"url/" . $anzeigennummer}) 
		{
			DEBUG $anzeigennummer;
      			DEBUG "Already notified";
			next;
		}

		jabber_send($message);
		$SEEN{"url/" . $anzeigennummer}++;
	}	
}


###########################################
sub jabber_send {
###########################################
    my($message) = @_;

    my $c = Net::Jabber::Client->new();

    $c->SetCallBacks(presence => sub {});

    my $status = $c->Connect(
        hostname => $JABBER_SERVER,
        port     => $JABBER_PORT,
    );

    LOGDIE "Can't connect: $!" 
        unless defined $status;

    my @result = $c->AuthSend(
        username => $JABBER_ID,
        password => $JABBER_PASSWD,
        resource => $config->param(-block=>'jabber')->{my_resource},
    );

    LOGDIE "Can't log in: $!" 
        unless $result[0] eq "ok";

#    $c->PresenceSend();

    my $m = Net::Jabber::Message->new();
    my $jid = "$JABBER_ID" . '@' .
              "$JABBER_SERVER/".$config->param(-block=>'jabber')->{other_resource};
    $m->SetBody($message);
    $m->SetTo($jid);
    DEBUG "Jabber to $jid: $message";
    my $rc = $c->Send($m, 1);

    $c->Disconnect;
}

