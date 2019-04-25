# (C) 1992-2016 Altera Corporation. All rights reserved.                         
# Your use of Altera Corporation's design tools, logic functions and other       
# software and tools, and its AMPP partner logic functions, and any output       
# files any of the foregoing (including device programming or simulation         
# files), and any associated documentation or information are expressly subject  
# to the terms and conditions of the Altera Program License Subscription         
# Agreement, Altera MegaCore Function License Agreement, or other applicable     
# license agreement, including, without limitation, that your use is for the     
# sole purpose of programming logic devices manufactured by Altera and sold by   
# Altera or its authorized distributors.  Please refer to the applicable         
# agreement for further details.                                                 
    


# Altera SDK for HLS compilation.
#  Inputs:  A mix of sorce files and object filse
#  Output:  A subdirectory containing: 
#              Design template
#              Verilog source for the kernels
#              System definition header file
#
# 
# Example:
#     Command:       a++ foo.cpp bar.c fum.o -lm -I../inc
#     Generates:     
#        Subdirectory a.out.prj including key files:
#           *.v
#           <something>.qsf   - Quartus project settings
#           <something>.sopc  - SOPC Builder project settings
#           kernel_system.tcl - SOPC Builder TCL script for kernel_system.qsys 
#           system.tcl        - SOPC Builder TCL script
#
# vim: set ts=2 sw=2 et

      BEGIN { 
         unshift @INC,
            (grep { -d $_ }
               (map { $ENV{"ALTERAOCLSDKROOT"}.$_ }
                  qw(
                     /host/windows64/bin/perl/lib/MSWin32-x64-multi-thread
                     /host/windows64/bin/perl/lib
                     /share/lib/perl
                     /share/lib/perl/5.8.8 ) ) );
      };


use strict;
require acl::File;
require acl::Pkg;
require acl::Env;

my $prog = 'a++';
my $return_status = 0;

#Filenames
my @source_list = ();
my @object_list = ();
my @tmpobject_list = ();
my @fpga_IR_list = ();
my @tb_IR_list = ();
my @cleanup_list = ();
my @component_names = ();

my $project_name = undef;
my $project_log = undef;
my $executable = undef;
my $board_variant=undef;
my $family = undef;
my $speed_grade = undef;
my $optinfile = undef;
my $pkg = undef;

#directories
my $orig_dir = undef; # path of original working directory.
my $g_work_dir = undef; # path of the project working directory as is.

# Executables
my $clang_exe = $ENV{'ALTERAOCLSDKROOT'}."/linux64/bin"."/aocl-clang";
my $opt_exe = $ENV{'ALTERAOCLSDKROOT'}."/linux64/bin"."/aocl-opt";
my $link_exe = $ENV{'ALTERAOCLSDKROOT'}."/linux64/bin"."/aocl-link";
my $llc_exe = $ENV{'ALTERAOCLSDKROOT'}."/linux64/bin"."/aocl-llc";
my $sysinteg_exe = $ENV{'ALTERAOCLSDKROOT'}."/linux64/bin"."/system_integrator";

#Flow control
my $emulator_flow = 0;
my $simulator_flow = 0;
my $RTL_only_flow_modifier = 0;
my $object_only_flow_modifier = 0;
my $soft_ip_c_flow_modifier = 0; # Hidden option for soft IP compilation
my $preprocess_only = 0;
my $macro_type_string = "";
my $verilog_gen_only = 0; # Hidden option to only run the Verilog generator
my $cosim_debug = 0;

# Quartus Compile Flow
my $qii_flow = 0;
my $qii_vpins = 1;
my $qii_io_regs = 1;
my $qii_device = "Stratix V";
my $qii_seed = undef;
my $qii_fmax_constraint = undef;

# Flow modifier
my $target_x86 = 0; # Hidden option for soft IP compilation to target x86
my $griffin_HT_flow = 0; # Use the DSPBA backend in place of HDLGen - high throughput (HT) flow
my $griffin_folding_flow = 0; # Use the DSPBA backend in place of HDLGen - folding flow
my $griffin_flow = 0; # Use the DSPBA backend in place of HDLGen - this should be set in either of the griffin flows (HT or folding)

#Output control
my $verbose = 0; # Note: there are three verbosity levels now 1, 2 and 3
my $disassemble = 0; # Hidden option to disassemble the IR
my $dotfiles = 0;
my $save_tmps = 0;
my $debug_symbols = 0;      # Debug info enabled?
my $time_log = undef; # Time various stages of the flow; if not undef, it is a 
                      # file handle (could be STDOUT) to which the output is printed to.

#Command line support
my @cmd_list = ();
my @parseflags=();
my @linkflags=();
my @additional_opt_args   = (); # Extra options for opt, after regular options.
my @additional_llc_args   = ();
my @additional_sysinteg_args = ();

my $opt_passes = '--acle ljg7wk8o12ectgfpthjmnj8xmgf1qb17frkzwewi22etqs0o0cvorlvczrk7mipp8xd3egwiyx713svzw3kmlt8clxdbqoypaxbbyw0oygu1nsyzekh3nt0x0jpsmvypfxguwwdo880qqk8pachqllyc18a7q3wp12j7eqwipxw13swz1bp7tk71wyb3rb17frk3egwiy2e7qjwoe3bkny8xrrdbq1w7ljg70g0o1xlbmupoecdfluu3xxf7l3dogxfs0lvm7jlzqjvo33gclly3xxf7mi8p32dc7udmirekmgvoy1bknyycrgfhmczpyxgf0wvz7jlzmy8p83kfnedxz2azqb17frk77qdiyxlkmh8ithkcluu3xxf7nvyzs2kmegdoyxlctgfptck3nt0318a7mcyz1xgu7uui3rezlg07ekh3lqjxtgdmnczpy2jtehdo3xyctgfpthjmljpbzgdmlb17frkuww0zwreeqapzkhholuu3xxf7nz8p3xguwypp3gw7mju7atjbnhdxmrjumipprxdceg0z880qqk8z2tk7qjjxbxacnzvpfxbbyw0otrebma8z2hdolkwx18a7m8jorxbbyw0o72eona8iekh3nyvb1rzbtijz82hkwhjibgwklgfptchqlyvc7rahm8w7ljg7wldzzxu13svz0cg1mt8c8gssmxw7ljg70tjzwgukmkyo03k7qjjxwgfzmb0ogrgswtfmirezqspo23kfnuwb1rdbtijz3gffwhpom2e3ldjpacvorlvcqgskq10pggju7ryomx713svzkhh3qhvccgammzpplxbbyw0ow2ekmavzuchfntwxzga33czpyrfu0evzp2qmqwvzltk72tfxm2kbmbjo8rg70qpow2wctgfptchhnl0b18a7q8vpm2kc7uvm7jlzma8pt3h72tfxmrafmiwoljg70kyitrykmrvzj3bknywbp2kbm8wpdxgc0uui0x1ctgfptchhnl0b18a7m3pp8rduwk0ovx713svzkhh3qhvccgammzpplxbbyw0obgl3mt8z2td72tfxmrafmiwoljg70qjobrlumju7atjfnljxwgpsmv0zlxgbwkpioglctgfpttkbql0318a7mo8zark37swiyxyctgfpttd3ny0b0jpsmvypfrfc7rwizgekmsyzy1bknypxuga3nczpyxdtwgdo1xwkmsjzy1bknyvcc2kmnc0prxdbwudmirecnujp83jcnuwbzxasqb17frkc0gdo880qqk8zwtjoluu3xxf7nz8p3xguwypp3gw7mju7atjqllvbyxffmodzgggbwtfmireznrpokcdorlvc8gd1qc87frk3egwiwrl3lw0oetd72tfxmxdhmidzrxgc0rdo880qqkvzshh3qhyx12kzmcw7ljg7wrporgukqgpoy1bknyvcc2aoncdom2vs0rpiogu3qgfpt3ghngpb18a7q3vpljg70qyiwgukmsvoktj3quu3xxfhmivolgfbyw0oy2qclgvoy1bknyybx2kfqo0pljg70rvi1glqqgwp3cvorlvc8xdon38zt8vs0rjiorlclgfpttdqnq0bvgsom7w7ljg7we0otrubmju7atjfnljxwgpsmv8ofgffweji880qqkvok3h7qq8x2gh7qxvzt8vs0r0z3recnju7atjclgdx0jpsmv8pl2g7whppoxu3nju7atjqllvbyxffmodzgggbwtfmiresqryp83bknywbp2kbmb0zgggzwtfmire3quyzy1bkny8c8xfbqb17frk77qdiyxlkmh8ithkcluu3xxfuqijomrkf0e8obgl1mju7atj3qhpbzrkbtijzq2j1wudmirecnujp0thzmf0b1xk33czpyrjh0w8o1xl3qkyzy1bknyvcc2a7l38plgfz0uvm7jlzmk8z2hdqntpb0jpsmv8ze2hbyw0oyrlkmswoehdorlvc72kzmczpy2ks0tjikrukqu07ekh3nuwxtgfun887frkuwwjibgl1mju7atjknlpbb2kbq3w7ljg70edorrw1muyz03f1ql0318a7mzppm2jmeypo32wznju7atjznrdbugd33czpyxfm7wdioxy1quwoucfqnyvb0jpsmvyzyxgbyw0oprlbmgy7atj3qhjxlgdbtijzgggcegpiirukqkvoekh3nuwc8rzbtijzh2kswuji720qqkyzl3g3nuwxvxk33czpyxdm7tyitgwemuypekh3ntdczxf1qo0p8xbbyw0oprl7lgpotthklg0318a7qcjzlxbbyw0oprl7lgpotthknjwb0jpsmvyzsrd10s0z7jlzmuyzfthbmty3xxfkmc8pljg70qyiwgukmsvoktj3quu3xxfmnc8pdgdb0uui3rlemky7atjmnyvc1xk7ncjot8vs0rjo32wctgfpttd3nuwx72kmncwosxbbyw0o0re1mju7atj7qj8xr2bmncvzt8vs0r8z72lemtyzekh3nedxzrjumb0pggs1wkpiogl13svz3cfhljycqrzbtijz3gff0ewiw2wcnu8pncvorlvc7rd7mcw7ljg7wewioxu13svz33gslkwxz2dulb17frk3eqpi7jlzqkjpuchonjvcz2azqb17frk77qdiyxlkmh8ithkcluu3xxfuqijomrkf0e8obgl1mju7atjznyyc0jpsmvpzgxsbehdmireoqdwot3j3qhvb0jpsmv0pa2jk0uui3rucna8p0cfolj0318a7q28z12ho0svm7jlzqjwo0hdqlyybygd3l8vp32kz0tjzbrlqmju7atjclgdx0jpsmv0zwgdb7uvm7jlzmgvzecvorlvcqgskq10pggju7ryomx713svzdtdzqjybmrjuqxyit8vs0rpiiru3lkjpfhjqllyc18a7qivpljg7wjvm7jlzquvzuchmlj8xagdbtijzs2km7ydo7jlzqjjzqhdonr8cygd7lb17frk77rpop2eonuyz8ch72tfxmrd7mcw7ljg7wypij2yclgfpthjqlhvc7xkcn8w7ljg7wewiq2wolujokcf3le0318a7m8jzrxg1wgpig2wctgfpthhhljyxvxk33czpyxj70uvm7jlzqjwzt3k72tfxmxdoliw7ljg7wu0o7x713svzkhh3qhvccgammzpplxbbyw0oygueqhpou3horlvc3rafqvyzs2vs0rdi72lctgfptcd1mljclgfkmczpyrjh0w8o1xl13svzf3ksntfxmgj7nbvzlxbbyw0owgukmt8puchorlvcbgfclzw7ljg70yyzix713svz33gslkwxz2dunczpygj3etfmire3qkyzy1bkny8xxrdbq7jo02k3ehpiirwctgfpttfqnevcbrzbtijzmgf1ww0znrlolay7atj7qj8xxrjoqb17frkh0wwiy20qqkvok3h7qq8x2gh33czpyxg70g0z1x713svzf3kfnljxwrzbtijz72jm7qyokx713svzdthhlky3xxf7nz8p3xguwypp880qqkwpttd3mu0318a7qvdzegfb0hdmirebmsdpscfmlhyc0jpsmv0zdxdbyw0o3gw7qgfpthj1lrpb1gk33czpygkm7tyi3xq13svztthklgyclxkumipp1vbbyw0o0re1mju7atjqllvbyxffmodzgggbwtfmiremlgvz0th1mepv1gpsmvjplgfs0uji880qqkdoehdqlr8v0jpsmvvz7gg38uui32qqquwotthsly8xxgd33czpyxj70uvm7jlzmtyz23gbnf0318a7q88zargo7udmire3qg8zw3bknyvbyxamncjot8vs0rjo32wctgfptchhnl0b18a7qc8zs2jc7qwiix713svzn3k1medcfrzbtijza2jm7ydo7jlzmypoeckqny8cygdcmczpyrfc7w8z7ructgfptck3nt0318a7mzpp8xd70wdi22qqqg07ekh3ljycwraumvyzm2jbyw0opru1nju7atjmltvc1rzbtijzs2h70evm7jlzmajpscdorlvcmxakqvypf2j38uui3xlkqkypy1bknydb12kuqxyit8vs0rjiorlclgfptcf1me0bmxabli0oljg70tyiirl3ljwoecvorlvcm2f3lb17frko7u8zbgwknju7atjqllvbyxffmodzgggbwtfmire7mtdpy1bknyvbzga3loype2s7wywo880qqkypehdcntpb1rjbl8ppt8vs0r0zb2lcna8pl3a3lrjc0jpsmv0pdrdbwg0zq2q3lk0py1bknyjcr2a33czpyxdm7qyzb2etqgfpt3hmlh0x0jpsmv0zy2j38uui3gy1mu8pl3a72tfxm2kbqc8oy2jbyw0or2wzlsyo2tjonj0318a7qcjzlxbbyw0ol2wolddzbcvorlvc7rdqm3jom2vs0r0zbgt1qu07ekh3nj8xbrkhmzpzxrko0yvm7jlzmajpm3k1mjjbzrj7qzw7ljg70rvi1glqqgwpekh3ly8cl2kumcdoljg70qyit2wonr8pshh72tfxmraumv8pt8vs0rdiyxwctgfpt3jklljxygfcnc87frk70wpop2wzlk8patkorlvcnxabli0z8xbbyw0oy2qzqfy7atjsntyx18a7mvvpfgju0yvm7jlzmtyz23gbnf0318a7qoypy2g38uui3rykqdvzfcvorlvcvxa1qcjomrgm7u0zw2ttqg07ekh3lqjb3rauqijolgfcetfmireolgypucfolj8x7rauq08zt8vs0rjo32wctgfpthjmljpbzgdmn80oxxgbwtfmire3qkyzy1bknypb1rjtm2vow2hcwtfmire7lddpy1bknyjbc2kemz0ol2gbyw0obgl3nu8patdqnyvb18a7qovp02jm7u8z880qqkype3hhlj8vqrjmncyza2hs0yvm7jlzmajpuck3qhjxlgd7l3yis2j38uui3ruzqjwpuhd1mtwcuxfcnzvpfxbbyw0o3rlqmtyz2cforlvcz2acncvzlgfbyw0oz2ytmr8p8chqntpbqrzbtijzggg7ek0oo2loqddpecvorlvc8xfbqb17frk1wu8ieru3lgfpttdqldycqrzbtijz72jm7qyokx713svzlcdorlvcpgfmlc8zf2jcwtfmiremqrvoe3bknywblgszmippd2gbwk8zbre13svzl3fknywbzxasm8w7ljg7wydzt2w13svzuckznjybngpsmvpzngg7wkpioglznju7atjznlybnrabmczpyxfb7evz7jlzmh0oekh3nhdxzrj33czpy2hs0gjz3rlumk8pa3k72tfxmrd7mcw7ljg7wyvz320qqkwzetjhnq0bcxkuq3ypdgg38uui32qqquwotthsly8xxgd33czpyxj70uvm7jlzmh0ot3bknyvcc2aoncdo82hfwwdmireclrvojcvorlvc2rk7mczpyrkfwwyz7guzldjpa3bknypb1gafq2yzsxbbyw0obglznrvzs3h1nedx1rzbtijzqrkbwtfmiremmyvzekh3lt8vxgfkmzjzljg70tjibrwqmju7atjqllvbyxffmodzgggbwtfmire3qkyzy1bknyjcr2a33czpyrfu0evzp2qmqwvzltk72tfxmxkumowos2ho0sdmiremmy07ekh3ltvc1rzbtijzggg7ek0oo2loqddpecvorlvc8xfbqb17frkm7ujoere1qgfptckolkycxrdbqijzl2vs0rjobru3ljdpt3k72tfxmrafmiwoljg70gpizxutqddzbcvorlvc72kmnbyiljg7wh8zbgyctgfpthdonqjxrgdbtijznggz7tyiw2w3qgfpttjmlqwxqrzbtijzsrg1wu0zwrlolgvo03afnt0318a7q8vpsxgbyw0oy2qclgwpkhholuu3xxfuqijomrkf0e8obgl1mju7atjznyyc0jpsmvyzfggfwkpow2w13svzf3ksltycwrzbtijzrggs0wjz1xy1qgfpttjenudxxgdhmczpyxjbwhdoixw1msvzk3k3quu3xxf7nvyp7xbbyw0ongw7ng07ekh3njwxrrzbtijz3gfb0uui3xleqs0oekh3lk8xwgdhmzppgggzwtfmireolgypshfontfxmrdbl10pgrk1wkdo7jlzmgpzqcvorlvc32jsqb17frkuww0zwreeqapzkhholuu3xxfcmzppm2j38uui32e3qkyzy1bknyvbmgsolb17frkh0wwiy20qqk0okcdolq8xxgssmxw7ljg70qyitxyzqsypr3gknt0318a7qcjzlxbbyw0or2wuqsdoe3bknywcurkhmzjzrxdb0uui3xwoqh07ekh3nj8xbrkhmzpzxrko0yvm7jlzmajpm3k1mjjbzrj7qzw7ljg7wuwiw20qqkvzltkorlvcvxafq187frk37qvz7xlkms8patk72tfxmxdbq187frkh0wwz7gukmsjzy1bkny8xxxkcnvvpagkuwwdo880qqkvok3h7qq8x2gh7qxvzt8vs0rjo32wctgfpthk7mtfxmrs1q80zlggbwudmirebqkvz73h72tfxm2d3nczpyxh1wgjo7gl1mgy7atjznlwb0jpsmvypfrfc7rwizgekmsyzy1bknyvbzga3loype2s7wywo880qqkwzt3k72tfxmgfcqp8o8xdbyw0ot2qslgvoy1bknydb12kuqxyit8vs0ryoprlbmr8patk7ml8xxrj7l3yis2j38uui3reolg8z03korlvcqrj1qo0pljg7wy8z72w13svztchomjwb12k7lb17frkm7ujoere1qgfpthkmlljxurj33czpygkm7upoc20qqkype3hznt0b0jpsmv0zy2j38uui3gu1qujp7hd3nty3xxf7lzyz12hs0yvm7jlzqkwpe3jknh0b18a7m8vpexdbyw0obxuctgfptcfeljjxuxdtq18om2vs0rvzr2qqmr07ekh3lgyclgsom7w7ljg7wyvzm2emlgpokhkqquf2x';

# device spec differs from board spec since it
# can only contain device information (no board specific parameters,
# like memory interfaces, etc)
my @llvm_board_option = ();

# On Windows, always use 64-bit binaries.
# On Linux, always use 64-bit binaries, but via the wrapper shell scripts in "bin".
#my $qbindir = ( $^O =~ m/MSWin/ ? 'bin64' : 'bin' );

# For messaging about missing executables
#my $exesuffix = ( $^O =~ m/MSWin/ ? '.exe' : '' );

sub append_to_log { #filename ..., logfile
    my $logfile= pop @_;
    open(LOG, ">>$logfile") or mydie("Couldn't open $logfile for appending.");
    foreach my $infile (@_) {
      open(TMP, "<$infile")  or mydie("Couldn't open $infile for reading.");
      while(my $l = <TMP>) {
        print LOG $l;
      }
      close TMP;
    }
    close LOG;
}

sub print_file { #filename ...
    foreach my $infile (@_) {
      open(TMP, "<$infile")  or mydie("Couldn't open $infile for reading.");
      while(my $l = <TMP>) {
        print $l;
      }
      close TMP;
    }
}

sub mydie(@) {
    if(@_) {
        print STDERR "Error: ".join("\n",@_)."\n";
    }
    chdir $orig_dir if defined $orig_dir;
    remove_named_files(@cleanup_list) unless $save_tmps;
    exit 1;
}

sub myexit(@) {
    print STDERR "Success: ".join("\n",@_)."\n" if $verbose>1;
    chdir $orig_dir if defined $orig_dir;
    remove_named_files(@cleanup_list) unless $save_tmps;
    exit 0;
}

# Functions to execute external commands, with various wrapper capabilities:
#   1. Logging
#   2. Time measurement
# Arguments:
#   @_[0] = { 
#       'stdout' => 'filename',   # optional
#        'title'  => 'string'     # used mydie and log 
#     }
#   @_[1..$#@_] = arguments of command to execute

sub mysystem_full($@) {
    my $opts = shift(@_);
    my @cmd = @_;

    my $out = $opts->{'stdout'};
    my $title = $opts->{'title'};
    my $err = $opts->{'stderr'};

    # Log the command to console if requested
    print STDOUT "============ ${title} ============\n" if $title && $verbose>1; 
    if ($verbose >= 2) {
      print join(' ',@cmd)."\n";
    }

    # Replace STDOUT/STDERR as requested.
    # Save the original handles.
    if($out) {
      open(OLD_STDOUT, ">&STDOUT") or mydie "Couldn't open STDOUT: $!";
      open(STDOUT, ">>$out") or mydie "Couldn't redirect STDOUT to $out: $!";
      $| = 1;
    }
    if($err) {
      open(OLD_STDERR, ">&STDERR") or mydie "Couldn't open STDERR: $!";
      open(STDERR, ">>$err") or mydie "Couldn't redirect STDERR to $err: $!";
      select(STDERR);
      $| = 1;
      select(STDOUT);
    }

    # Run the command.
    my $start_time = time();
    my $retcode = system(@cmd);
    my $end_time = time();

    # Restore STDOUT/STDERR if they were replaced.
    if($out) {
      close(STDOUT) or mydie "Couldn't close STDOUT: $!";
      open(STDOUT, ">&OLD_STDOUT") or mydie "Couldn't reopen STDOUT: $!";
    }
    if($err) {
      close(STDERR) or mydie "Couldn't close STDERR: $!";
      open(STDERR, ">&OLD_STDERR") or mydie "Couldn't reopen STDERR: $!";
    }

    # Dump out time taken if we're tracking time.
    if ($time_log && $opts->{'time'}) {
      my $time_label = $opts->{'time-label'};
      if (!$time_label) {
        # Just use the command as the label.
        $time_label = join(' ',@cmd);
      }

      log_time ($time_label, $end_time - $start_time);
    }

    my $result = $retcode >> 8;

    if($retcode != 0) {
      if ($result == 0) {
      # We probably died on an assert, make sure we do not return zero
	$result=-1;
      } 
      my $loginfo = "";
      if($err && $out && ($err != $out)) {
        $loginfo = "\nSee $err and $out for details.";
      } elsif ($err) {
        $loginfo = "\nSee $err for details.";
      } elsif ($out) {
        $loginfo = "\nSee $out for details.";
      }
      print("HLS $title FAILED.$loginfo\n");
    }
    return ($result);
}

sub log_time($$) {
  my ($label, $time) = @_;
  if ($time_log) {
    printf ($time_log "[time] %s ran in %ds\n", $label, $time);
  }
}

sub save_pkg_section($$$) {
    my ($pkg,$section,$value) = @_;
    # The temporary file should be in the compiler work directory.
    # The work directory has already been created.
    my $file = $g_work_dir.'/value.txt';
    open(VALUE,">$file") or mydie("Can't write to $file: $!");
    binmode(VALUE);
    print VALUE $value;
    close VALUE;
    $pkg->set_file($section,$file)
      or mydie("Can't save value into package file: $acl::Pkg::error\n");
    acl::File::remove_tree($file); # Remove immediatly don't wait for cleanup
}

sub disassemble ($) {
    my $file=$_[0];
    if ( $disassemble ) {
      mysystem_full({'stdout' => ''}, "llvm-dis ".$file ) == 0 or mydie("Cannot disassemble:".$file."\n"); 
    }
}

sub get_acl_board_hw_path {
    return "$ENV{\"ALTERAOCLSDKROOT\"}/share/models/bm";
}

sub remove_named_files {
    foreach my $fname (@_) {
      acl::File::remove_tree( $fname, { verbose => ($verbose>2), dry_run => 0 } )
         or mydie("Cannot remove $fname: $acl::File::error\n");
    }
}

sub unpack_object_files(@) {
    my $work_dir= shift;
    my @list = ();
    my $file;

    acl::File::make_path($work_dir) or mydie($acl::File::error.' While trying to create '.$work_dir);

    foreach $file (@_) {
      my $corename = get_name_core($file);
      my $pkg = get acl::Pkg($file);
      if (!$pkg) { #should never trigger
        push @list, $file;
      } else {  
        if ($pkg->exists_section('.hls.fpga.parsed.ll')) {
          my $fname=$work_dir.'/'.$corename.'.fpga.ll';
          $pkg->get_file('.hls.fpga.parsed.ll',$fname);
          push @fpga_IR_list, $fname;
          push @cleanup_list, $fname;
        }
        if ($pkg->exists_section('.hls.tb.parsed.ll')) {
          my $fname=$work_dir.'/'.$corename.'.tb.ll';
          $pkg->get_file('.hls.tb.parsed.ll',$fname);
          push @tb_IR_list, $fname;
          push @cleanup_list, $fname;
        } else {
          # Regular object file 
          push @list, $file;
        } 
      }
    }
    @object_list=@list;

    if (@tb_IR_list + @fpga_IR_list == 0){
      #No need for project directory, remove it
      push @cleanup_list, $work_dir;
    }
}

sub get_name_core($) {
    my  $base = acl::File::mybasename($_[0]);
    $base =~ s/[^a-z0-9_\.]/_/ig;
    my $suffix = $base;
    $suffix =~ s/.*\.//;
    $base=~ s/\.$suffix//;
    return $base;
}

sub setup_linkstep () {
    # Setup project directory and log file for reminder of compilation
    # We could deduce this from the object files, but that is known at unpacking
    # that requires this to be defined.
    # Only downside of this is if we use a++ to link "real" objects we also reate
    # create an empty project directory
    if (!$project_name) {
        $project_name = 'a.out';
    }
    $g_work_dir = ${project_name}.'.prj';
    # No turning back, remove anything old
    remove_named_files($g_work_dir,'modelsim.ini',$project_name);

    acl::File::make_path($g_work_dir) or mydie($acl::File::error.' While trying to create '.$g_work_dir);
    $project_log=${g_work_dir}.'/'.get_name_core(${project_name}).'.log';
    $project_log = acl::File::abs_path($project_log);
    # Remove immediatly. This is to make sure we don't pick up data from 
    # previos run, not to clean up at the end 

    # Individual file processing done, populates fpga_IR_list and  tb_IR_list
    unpack_object_files($g_work_dir, @object_list);

}

sub preprocess () {
    my $acl_board_hw_path= get_acl_board_hw_path($board_variant);

    # Make sure the board specification file exists. This is needed by multiple stages of the compile.
    my ($board_spec_xml) = acl::File::simple_glob( $acl_board_hw_path."/$board_variant" );
    my $xml_error_msg = "Cannot find Board specification!\n*** No board specification (*.xml) file inside ".$acl_board_hw_path.". ***\n" ;
    -f $board_spec_xml or mydie( $xml_error_msg );
    push @llvm_board_option, '-board';
    push @llvm_board_option, $board_spec_xml;
}

sub usage() {
    print <<USAGE;

Usage: a++ [<options>] <input_files> 
--version   Display compiler version information
-v          Verbose mode
-h,--help   Display this information
-c          Preprocess, parse and generate object files
-o <name>   Place the output into <name> and <name>.prj
-g          Generate debug information
-I<dir>     Add directory to the end of the main include path
-L<dir>     Add directory dir to the list of directories to be searched for -l
-l<library> Search the library named library when linking
-D<macro>[=<val>]   
            Define a <macro> with <val> as its value.  If just <macro> is
            given, <val> is taken to be 1
-march=<arch> 
            Generate code for <arch>, <arch> is one of:
              x86-64, altera
--device <device>       
            Specifies the FPGA device or family to use, <device> is one of:
              "Stratix V", "Arria 10", "Cyclone V", "Max 10", or any valid
              part number from those FPGA families
--component <components>
            Comma-separated list of function names to synthesize to RTL
--rtl-only  Generate RTL for components without testbench
--clock <clock_spec>
            Optimize the RTL for the specified clock frequency or period
--fp-relaxed 
            Relax the order of arithmetic operations
--fpc       Removes intermediate rounding and conversion when possible
--promote-integers  
            Use extra FPGA resources to mimic g++ integer promotion
--cosim-debug 
            Enable full debug visibility and logging of all signals
--quartus-compile 
            Run HDL through a Quartus compilation
USAGE

}

sub version($) {
    my $outfile = $_[0];
    print $outfile "a++ Compiler for Altera High Level Synthesis\n";
    print $outfile "Version 0.2 Build 206\n";
    print $outfile "Copyright (C) 2016 Altera Corporation\n";
}

sub norm_family_str {
    my $strvar = shift;
    # strip whitespace
    $strvar =~ s/[ \t]//gs;
    # uppercase the string
    $strvar = uc $strvar;
    return $strvar;
}

sub device_get_family_no_normalization {  # DSPBA needs the original Quartus format
    my $qii_family_device = shift;
    my $family_from_quartus = `quartus_sh --tcl_eval get_part_info -family $qii_family_device`;
    # Return only what's between the braces, without the braces 
    ($family_from_quartus) = ($family_from_quartus =~ /\{(.*)\}/);
    chomp $family_from_quartus;
    return $family_from_quartus;
}

sub device_get_family {
    my $qii_family_device = shift;
    my $family_from_quartus = device_get_family_no_normalization( $qii_family_device );
    $family_from_quartus = norm_family_str($family_from_quartus);
    return $family_from_quartus;
}

sub device_get_speedgrade {  # DSPBA requires the speedgrade to be set, in addition to the part number
    my $device = shift;
    my $speed_grade_from_quartus = `quartus_sh --tcl_eval get_part_info -speed_grade $device`;
    mydie("Failed to determine speed grade of device $device\n") if (!defined $speed_grade_from_quartus);
    # Some speed grade results from quartus include the transciever speed grade appended to the core speed grade.
    # We extract the first character only to be sure that we have exclusively the core result.
    return "-".substr($speed_grade_from_quartus, 0, 1);  # Prepend '-' because DSPBA expects it
}

sub translate_device {
  my $qii_dev_family = shift;
    $qii_dev_family = norm_family_str($qii_dev_family);
    my $qii_device = undef;

    if ($qii_dev_family eq "ARRIA10") {
        $qii_device = "10AX115U1F45I1SG";
    } elsif ($qii_dev_family eq "STRATIXV") {
        $qii_device = "5SGSMD4E1H29I2";
    } elsif ($qii_dev_family eq "CYCLONEV") {
        $qii_device = "5CEFA9F23I7";
    } elsif ($qii_dev_family eq "MAX10") {
        $qii_device = "10M50DAF672I7G";
    } else {
        $qii_device = $qii_dev_family;
    }

    return $qii_device;
}

sub parse_family ($){
    my $family=$_[0];

    ### list of supported families
    my $SV_family = "STRATIXV";
    my $CV_family = "CYCLONEV";
    my $A10_family = "ARRIA10";
    my $M10_family = "MAX10";
    
    ### the associated reference boards
    my %family_to_board_map = (
        $SV_family  => 'SV.xml',
        $CV_family  => 'CV.xml',
        $A10_family => 'A10.xml',
        $M10_family => 'M10.xml',
      );

    my $supported_families_str;
    foreach my $key (keys %family_to_board_map) { 
      $supported_families_str .= "\n\"$key\" ";
    }

    my $board = undef;

    # if no family specified, then use Stratix V family default board
    if (!defined $family) {
        $family = $SV_family;
    }
    # Uppercase family string. 
    $family = norm_family_str($family);

    $board = $family_to_board_map{$family};
    
    if (!defined $board) {
        mydie("Unsupported device family: $family. \nSupported device families: $supported_families_str");
    }

    # set a default device if one has not been specified
    if (!defined $qii_device) {
        $qii_device = translate_device($family);
    }

    return ($family,$board);
}

sub save_and_report{
    my $filename = shift;
    my $pkg = create acl::Pkg(${g_work_dir}.'/'.get_name_core(${project_name}).'.aoco');

    # Visualization support
    if ( $debug_symbols ) { # Need dwarf file list for this to work
      my $files = `file-list \"$g_work_dir/$filename\"`;
      my $index = 0;
      foreach my $file ( split(/\n/, $files) ) {
          save_pkg_section($pkg,'.acl.file.'.$index,$file);
          $pkg->add_file('.acl.source.'. $index,$file)
            or mydie("Can't save source into package file: $acl::Pkg::error\n");
          $index = $index + 1;
      }
      save_pkg_section($pkg,'.acl.nfiles',$index);
    }

    # Save Memory Architecture View JSON file 
    my $mav_file = $g_work_dir.'/mav.json';
    if ( -e $mav_file ) {
      $pkg->add_file('.acl.mav.json', $mav_file)
          or mydie("Can't save mav.json into package file: $acl::Pkg::error\n");
      push @cleanup_list, $mav_file;
    }
    # Save Area Report JSON file 
    my $area_file = $g_work_dir.'/area.json';
    if ( -e $area_file ) {
      $pkg->add_file('.acl.area.json', $area_file)
          or mydie("Can't save area.json into package file: $acl::Pkg::error\n");
      push @cleanup_list, $area_file;
    }
    my $area_file_html = $g_work_dir.'/area.html';
    if ( ! -e $area_file_html and $verbose > 0 ) {
      print "Missing area report information\n";
    }
    # Get rid of SPV JSON file ince we don't use it 
    my $spv_file = $g_work_dir.'/spv.json';
    if ( -e $spv_file ) {
      push @cleanup_list, $spv_file;
    }

    # Move over the Optimization Report to the log file 
    my $opt_file = $g_work_dir.'/opt.rpt';
    if ( -e $opt_file ) {
      append_to_log( $opt_file, $project_log );
      push @cleanup_list, $opt_file;
    }

    chdir $g_work_dir or mydie("Can't change into dir $g_work_dir: $!\n");
    chdir $orig_dir or mydie("Can't change into dir $orig_dir: $!\n");
    
    # Get utilization numbers from area.json. Initialize to -999
    # because we want to stop parsing the JSON after each category gets 
    # gets a value. The JSON contains utilzation values per kernel so 
    # only the first value for each category is for the whole system.
    my $util = -999;
    my $ffs = -999;
    my $rams = -999;
    my $dsps = -999;
    open my $area_json, '<', $area_file;
    while (($util == -999 or $ffs == -999 or $rams == -999 or $dsps == -999) and 
           my $json_line = <$area_json>) {
      if ($json_line =~ m/\"ff_util_%\":(\d+(.\d+)?)/) {  
        $ffs = $1;
      } elsif ($json_line =~ m/\"ram_util_%\":(\d+(.\d+)?)/) {
         $rams = $1;
      } elsif ($json_line =~ m/\"dsp_util_%\":(\d+(.\d+)?)/) {
         $dsps = $1;
      } elsif ($json_line =~ m/\"logic_util_%\":(\d+(.\d+)?)/) {
         $util = $1;
      }
    }
    close $area_json;
    # Round these numbers properly instead of just truncating them.
    $util = int($util + 0.5);
    $ffs = int($ffs + 0.5);
    $rams = int($rams + 0.5);
    $dsps = int($dsps + 0.5);
    
    my $report_file = $g_work_dir.'/report.out';
    open LOG, '>'.$report_file;
    printf(LOG "\n".
        "+--------------------------------------------------------------------+\n".
        "; Estimated Resource Usage Summary                                   ;\n".
        "+----------------------------------------+---------------------------+\n".
        "; Resource                               + Usage                     ;\n".
        "+----------------------------------------+---------------------------+\n".
        "; Logic utilization                      ; %4d\%                     ;\n".
        "; Dedicated logic registers              ; %4d\%                     ;\n".
        "; Memory blocks                          ; %4d\%                     ;\n".
        "; DSP blocks                             ; %4d\%                     ;\n".
        "+----------------------------------------+---------------------------;\n", 
        $util, $ffs, $rams, $dsps);
    close LOG;
    
    append_to_log ($report_file, $project_log);
    push @cleanup_list, $report_file;
}

sub clk_get_exp {
    my $var = shift;
    my $exp = $var;
    $exp=~ s/[\.0-9 ]*//;
    return $exp;
}

sub clk_get_mant {
    my $var = shift;
    my $mant = $var;
    my $exp = clk_get_exp($mant);
    $mant =~ s/$exp//g;
    return $mant;
} 

sub clk_get_fmax {
    my $clk = shift;
    my $exp = clk_get_exp($clk);
    my $mant = clk_get_mant($clk);

    my $fmax = undef;

    if ($exp =~ /^GHz/) {
        $fmax = 1000000000 * $mant;
    } elsif ($exp =~ /^MHz/) {
        $fmax = 1000000 * $mant;
    } elsif ($exp =~ /^kHz/) {
        $fmax = 1000 * $mant;
    } elsif ($exp =~ /^Hz/) {
        $fmax = $mant;
    } elsif ($exp =~ /^ms/) {
        $fmax = 1000/$mant;
    } elsif ($exp =~ /^us/) {
        $fmax = 1000000/$mant;
    } elsif ($exp =~ /^ns/) {
        $fmax = 1000000000/$mant;
    } elsif ($exp =~ /^ps/) {
        $fmax = 1000000000000/$mant;
    } elsif ($exp =~ /^s/) {
        $fmax = 1/$mant;
    }
    if (defined $fmax) { 
        $fmax = $fmax/1000000;
    }
    return $fmax;
}

sub parse_args {
    my @user_parseflags = ();
    my @user_linkflags =();
    while ( $#ARGV >= 0 ) {
      my $arg = shift @ARGV;
      if ( ($arg eq '-h') or ($arg eq '--help') ) { usage(); exit 0; }
      elsif ( ($arg eq '--version') or ($arg eq '-V') ) { version(\*STDOUT); exit 0; }
      elsif ( ($arg eq '-v') ) { $verbose += 1; if ($verbose > 1) {$prog = "#$prog";} }
      elsif ( ($arg eq '-g') ) { $debug_symbols = 1;}
      elsif ( ($arg eq '-o') ) {
          # Absorb -o argument, and don't pass it down to Clang
          $#ARGV >= 0 or mydie("Option $arg requires a name argument.");
          $project_name = shift @ARGV;
      }
      elsif ( ($arg eq '--component') ) {
          $#ARGV >= 0 or mydie('Option --component requires a function name');
          push @component_names, shift @ARGV;
      }
      elsif ($arg eq '-march=emulator' || $arg eq '-march=x86-64') {
          $emulator_flow = 1;
      }
      elsif ($arg eq '-march=simulator' || $arg eq '-march=altera') {
          $simulator_flow = 1;
      }
      elsif ($arg eq '--RTL-only' || $arg eq '--rtl-only' ) {
          $RTL_only_flow_modifier = 1;
      }
      elsif ($arg eq '--cosim' ) {
          $RTL_only_flow_modifier = 0;
      }
      elsif ($arg eq '--cosim-debug') {
          $RTL_only_flow_modifier = 0;
          $cosim_debug = 1;
      }
      elsif ( ($arg eq '--clang-arg') ) {
          $#ARGV >= 0 or mydie('Option --clang-arg requires an argument');
          # Just push onto args list
          push @user_parseflags, shift @ARGV;
      }
      elsif ( ($arg eq '--opt-arg') ) {
          $#ARGV >= 0 or mydie('Option --opt-arg requires an argument');
          push @additional_opt_args, shift @ARGV;
      }
      elsif ( ($arg eq '--llc-arg') ) {
          $#ARGV >= 0 or mydie('Option --llc-arg requires an argument');
          push @additional_llc_args, shift @ARGV;
      }
      elsif ( ($arg eq '--optllc-arg') ) {
          $#ARGV >= 0 or mydie('Option --optllc-arg requires an argument');
          my $optllc_arg = (shift @ARGV);
          push @additional_opt_args, $optllc_arg;
          push @additional_llc_args, $optllc_arg;
      }
      elsif ( ($arg eq '--sysinteg-arg') ) {
          $#ARGV >= 0 or mydie('Option --sysinteg-arg requires an argument');
          push @additional_sysinteg_args, shift @ARGV;
      }
      elsif ( ($arg eq '--v-only') ) { $verilog_gen_only = 1; }

      elsif ( ($arg eq '-c') ) { $object_only_flow_modifier = 1; }

      elsif ( ($arg eq '--dis') ) { $disassemble = 1; }   
      elsif ($arg eq '--dot') {
        $dotfiles = 1;
      }
      elsif ($arg eq '--save-temps') {
        $save_tmps = 1;
      }
      elsif ($arg eq '--fold') {
        $griffin_folding_flow = 1;
        $griffin_flow = 1;
      }
      elsif ($arg eq '--grif') {
        $griffin_HT_flow = 1;
        $griffin_flow = 1;
      }
      elsif ( ($arg eq '--clock') ) {
          my $clk_option = (shift @ARGV);
          $qii_fmax_constraint = clk_get_fmax($clk_option);
          if (!defined $qii_fmax_constraint) {
              mydie("a++: bad value ($clk_option) for --clock argument\n");
          }
          push @additional_opt_args, '-scheduler-fmax='.$qii_fmax_constraint;
          push @additional_llc_args, '-scheduler-fmax='.$qii_fmax_constraint;
      }
      elsif ( ($arg eq '--fp-relaxed') ) {
          push @additional_opt_args, "-fp-relaxed=true";
      }
      elsif ( ($arg eq '--fpc') ) {
          push @additional_opt_args, "-fpc=true";
      }
      elsif ( ($arg eq '--promote-integers') ) {
          push @user_parseflags, "-fhls-int-promotion";
      }
      # Soft IP C generation flow
      elsif ($arg eq '--soft-ip-c') {
          $soft_ip_c_flow_modifier = 1;
          $simulator_flow = 1;
          $disassemble = 1;
      }
      # Soft IP C generation flow for x86
      elsif ($arg eq '--soft-ip-c-x86') {
          $soft_ip_c_flow_modifier = 1;
          $simulator_flow = 1;
          $target_x86 = 1;
          $opt_passes = "-inline -inline-threshold=10000000 -dce -stripnk -cleanup-soft-ip";
          $disassemble = 1;
      }
      elsif ($arg eq '--quartus-compile') {
          $qii_flow = 1;
      }
      elsif ($arg eq '--quartus-no-vpins') {
          $qii_vpins = 0;
      }
      elsif ($arg eq '--quartus-dont-register-ios') {
          $qii_io_regs = 0;
      }
      elsif ($arg eq "--device") {
          $qii_device = shift @ARGV;
          $qii_device = translate_device($qii_device);
          $family = device_get_family($qii_device); 
          if ($family eq "") {
               mydie("Device $qii_device is not known, please specify a known device\n");
          }
      }
      elsif ($arg eq "--quartus-seed") {
          $qii_seed = shift @ARGV;
      }
      elsif ($arg eq '--time') {
        if($#ARGV >= 0 && $ARGV[0] !~ m/^-./) {
          $time_log = shift(@ARGV);
        }
        else {
          $time_log = "-"; # Default to stdout.
        }
      }
      elsif ($arg =~ /^-[lL]/ or
             $arg =~ /^-Wl/) { 
          push @user_linkflags, $arg;
      }
      elsif ($arg =~ /^-I /) { # -Iinc syntax falls through to default below
          $#ARGV >= 0 or mydie("Option $arg requires a name argument.");
          push  @user_parseflags, $arg.(shift @ARGV);
      }
      elsif ( $arg =~ m/\.c$|\.cc$|\.cp$|\.cxx$|\.cpp$|\.CPP$|\.c\+\+$|\.C$/ ) {
          push @source_list, $arg;
      }
      elsif ( $arg =~ m/\.o$/ ) {
          push @object_list, $arg;
      } 
      elsif ($arg eq '-E') { #preprocess only;
          $preprocess_only= 1;
          $object_only_flow_modifier= 1;
          push @user_parseflags, $arg 
      } else {
          push @user_parseflags, $arg 
      }
    }

    if (@component_names) {
      push @user_parseflags, "-Xclang";
      push @user_parseflags, "-soft-ip-c-func-name=".join(',',@component_names);
    }

    # All arguments in, make sure we have at least one file
    (@source_list + @object_list) > 0 or mydie('No input files');
    if ($debug_symbols) {
      push @user_parseflags, '-g';
      push @additional_llc_args, '-dbg-info-enabled';
    } 

    if ($RTL_only_flow_modifier && $emulator_flow ) {
      mydie("a++: Invalid options combination of --rtl-only flag and -march=x86-64\n");
    }

    $qii_device = translate_device($qii_device);

    # only query the family name if using a sim flow,
    # currently this queries Quartus and takes about 10 seconds
    # on our development sessions.
    #
    if ($simulator_flow) { 
        $family = device_get_family($qii_device); 
        if ($family eq "") {
            mydie("Device $qii_device is not known, please specify a known device\n");
        }
    }

    ($family, $board_variant) = parse_family($family);

    # Make sure that the qii compile flow is only used with the altera compile flow
    if ($qii_flow and not $simulator_flow) {
        mydie("The --quartus-compile argument can only be used with -march=altera\n");
    }

    # The DSPBA folding and high throughput flows are mutually exclusive
    if ($griffin_HT_flow and $griffin_folding_flow) {
        mydie("The DSPBA high throughput (--grif) and folding (--fold) flows cannot be used simultaneously\n");
    }

    if ($dotfiles) {
      push @additional_opt_args, '--dump-dot';
      push @additional_llc_args, '--dump-dot'; 
      push @additional_sysinteg_args, '--dump-dot';
    }

    # caching is disabled for LSUs in HLS components for now
    # enabling caches is tracked by case:314272
    push @additional_opt_args, '-nocaching';
    push @additional_opt_args, '-noprefetching';

    $orig_dir = acl::File::abs_path('.');

    if ( $project_name ) {
      if ( $#source_list > 0 && $object_only_flow_modifier) {
        mydie("Cannot specify -o with -c and multiple soure files\n");
      }
    }
    
    # Check that this is a valid board directory by checking for a board model .xml 
    # file in the board directory.
    if (not $emulator_flow) {
      my $board_xml = get_acl_board_hw_path($board_variant).'/'.$board_variant;
      if (!-f $board_xml) {
        mydie("Board '$board_variant' not found!\n");
      }
    }
    # Consolidate some flags
    push (@parseflags, @user_parseflags);
    push (@parseflags,"-I$ENV{\"ALTERAOCLSDKROOT\"}/include");
    push (@parseflags,"-I$ENV{\"ALTERAOCLSDKROOT\"}/host/include");
    
    my $emulator_arch=acl::Env::get_arch();
    my $host_lib_path = acl::File::abs_path( acl::Env::sdk_root().'/host/'.${emulator_arch}.'/lib');
    push (@linkflags, @user_linkflags);
    push (@linkflags, '-lstdc++');
    push (@linkflags, '-L'.$host_lib_path);

}

sub fpga_parse ($$){  
    my $source_file= shift;
    my $objfile = shift;
    print "Analyzing $source_file for hardware generation\n" if $verbose;

    $pkg = undef;

    # OK, no turning back remove the old result file, so no one thinks we 
    # succedded. Can't be defered since we only clean it up IF we don't do -c
    acl::File::remove_tree($objfile);
    if ($preprocess_only || !$object_only_flow_modifier) { push @cleanup_list, $objfile; };

    $pkg = create acl::Pkg($objfile);
    push @object_list, $objfile;

    my $work_dir=$objfile.'.'.$$.'.tmp';
    acl::File::make_path($work_dir) or mydie($acl::File::error.' While trying to create '.$work_dir);
    push @cleanup_list, $work_dir;

    my $outputfile=$work_dir.'/fpga.ll';

    my @clang_std_opts2 = qw(-S -x hls -emit-llvm -DALTERA_CL -Wuninitialized -fno-exceptions);
    if ( $target_x86 == 0 ) { push (@clang_std_opts2, qw(-ccc-host-triple fpga64-unknown-linux)); }

    @cmd_list = (
      $clang_exe,
      ($verbose>2)?'-v':'',
      @clang_std_opts2,
      "-D__ALTERA_TYPE__=$macro_type_string",
      @parseflags,
      $source_file,
      $preprocess_only ? '':('-o',$outputfile)
    );

    $return_status = mysystem_full( {'title' => 'fpga Parse'}, @cmd_list);
    if ($return_status) {
        push @cleanup_list, $objfile; #Object file created
        mydie();
    }
    if (!$preprocess_only) {
        # add 
        $pkg->add_file('.hls.fpga.parsed.ll',$outputfile);
        push @cleanup_list, $outputfile;
    }
}

sub testbench_parse ($$) {
    my $source_file= shift;
    my $object_file = shift;
    print "Analyzing $source_file for testbench generation\n" if $verbose;

    my $work_dir=$object_file.'.'.$$.'.tmp';
    acl::File::make_path($work_dir) or mydie($acl::File::error.' While trying to create '.$work_dir);
    push @cleanup_list, $work_dir;

    #Temporarily disabling exception handling here, Tracking in FB223872
    my @clang_std_opts = qw(-S -emit-llvm  -x hls -O0 -DALTERA_CL -Wuninitialized -fno-exceptions);

    my @macro_options;
    @macro_options= qw(-DHLS_COSIMULATION -Dmain=__altera_hls_main);

    my $outputfile=$work_dir.'/tb.ll';
    @cmd_list = (
      $clang_exe,
      ($verbose>2)?'-v':'',
      @clang_std_opts,
      "-D__ALTERA_TYPE__=$macro_type_string",
      @parseflags,
      @macro_options,
      $source_file,
      $preprocess_only ? '':('-o',$outputfile)
      );

    $return_status = mysystem_full( {'title' => 'Sim Testbench Parse'}, @cmd_list);
    if ($return_status != 0) {
        push @cleanup_list, $object_file; #Object file created
        mydie();;
    }
    if (!$preprocess_only) {
        $pkg->add_file('.hls.tb.parsed.ll',$outputfile);
        push @cleanup_list, $outputfile;
    }
}

sub emulator_compile ($$) {
    my $source_file= shift;
    my $object_file = shift;
    print "Analyzing $source_file for emulation\n" if $verbose;
    @cmd_list = (
      $clang_exe,
      ($verbose>2)?'-v':'',
      qw(-x hls -O0 -DALTERA_CL -Wuninitialized -c),
      '-DHLS_EMULATION',
      "-D__ALTERA_TYPE__=$macro_type_string",
      $source_file,
      @parseflags,
      $preprocess_only ? '':('-o',$object_file)
    );
    
    mysystem_full(
      {'title' => 'Emulator compile'}, @cmd_list) == 0 or mydie();
    
    push @object_list, $object_file;
    if (!$object_only_flow_modifier) { push @cleanup_list, $object_file; };
}

sub generate_testbench(@) {
    my ($IRfile)=@_;
    print "Creating x86-64 testbench \n" if $verbose;

    my $resfile=$g_work_dir.'/tb.bc';
    my @flow_options= qw(-replacecomponentshlssim);
    
    @cmd_list = (
      $opt_exe,  
      @flow_options,
      @additional_opt_args,
      @llvm_board_option,
      '-o', $resfile,
      $g_work_dir.'/'.$IRfile );

    mysystem_full( {'title' => 'opt (host tweaks))'}, @cmd_list) == 0 or mydie();

    disassemble($resfile);
    
    @cmd_list = (
      $clang_exe,
      ($verbose>2)?'-v':'',
      qw(-B/usr/bin -fPIC -shared -O0),
      $g_work_dir.'/tb.bc',
      "-D__ALTERA_TYPE__=$macro_type_string",
      @object_list,
      '-Wl,-soname,a_sim.so',
      '-o', $g_work_dir.'/a_sim.so',
      @linkflags, qw(-lhls_cosim) );

    mysystem_full({'title' => 'clang (executable testbench image)'}, @cmd_list ) == 0 or mydie();

    # we used the regular objects, remove them so we don't think this is emulation
    @object_list=();
}

sub generate_fpga(@){
    my @IR_list=@_;
    print "Optimizing component(s) and generating Verilog and QIP files\n" if $verbose;

    my $linked_bc=$g_work_dir.'/fpga.linked.bc';

    # Link with standard library.
    my $early_bc = acl::File::abs_path( acl::Env::sdk_root().'/share/lib/acl/acl_early.bc');
    @cmd_list = (
      $link_exe,
      @IR_list,
      $early_bc,
      '-o',
      $linked_bc );
    
    mysystem_full( {'title' => 'Early Link'}, @cmd_list) == 0 or mydie();
    
    disassemble($linked_bc);
    
    # llc produces visualization data in the current directory
    chdir $g_work_dir or mydie("Can't change into dir $g_work_dir: $!\n");
    
    my $kwgid='fpga.opt.bc';
    my @flow_options = qw(-HLS);
    if ( $soft_ip_c_flow_modifier ) { push(@flow_options, qw(-SIPC)); }
    if ( $griffin_flow ) { push(@flow_options, qw(--grif --soft-elementary-math=false --fas=false --lower-gep)); }
    if ( $griffin_folding_flow ) { push(@flow_options, qw(--fold)); }
    my @cmd_list = (
      $opt_exe,
      @flow_options,
      split( /\s+/,$opt_passes),
      @llvm_board_option,
      @additional_opt_args,
      'fpga.linked.bc',
      '-o', $kwgid );
    
    mysystem_full( {'title' => 'Main Opt pass', 'time' => 1, 'time-label' => 'opt'}, @cmd_list ) == 0 or mydie();
    
    disassemble($kwgid);
    
    if ( $soft_ip_c_flow_modifier ) { myexit('Opt Step'); }

    my $lowered='fpga.lowered.bc';
    # Lower instructions to IP library function calls
    
    my @flow_options = qw(-HLS -insert-ip-library-calls);
    if ( $griffin_flow ) { push(@flow_options, qw(--grif --soft-elementary-math=false --fas=false --lower-gep)); }
    if ( $griffin_folding_flow ) { push(@flow_options, qw(--fold)); }
    @cmd_list = (
        $opt_exe,
        @flow_options,
        @additional_opt_args,
        $kwgid,
        '-o', $lowered);

    mysystem_full( {'title' => 'Lower to IP'}, @cmd_list ) == 0 or mydie();

    my $linked='fpga.linked2.bc';
    # Link with the soft IP library 
    my $late_bc = acl::File::abs_path( acl::Env::sdk_root().'/share/lib/acl/acl_late.bc');
    @cmd_list = (
      $link_exe,
      $lowered,
      $late_bc,
      '-o', $linked );

    mysystem_full( {'title' => 'Late library'}, @cmd_list)  == 0 or mydie();

    my $final = get_name_core(${project_name}).'.bc';
    # Inline IP calls, simplify and clean up
    @cmd_list = (
      $opt_exe,
      qw(-HLS -always-inline -add-inline-tag -instcombine -adjust-sizes -dce -stripnk),
      @llvm_board_option,
      @additional_opt_args,
      $linked,
      '-o', $final);

    mysystem_full( {'title' => 'Inline and clean up'}, @cmd_list) == 0 or mydie();

    disassemble($final);

    my $llc_option_macro = $griffin_flow ? ' -march=griffin ' : ' -march=fpga -mattr=option3wrapper -fpga-const-cache=1';
    my @llc_option_macro_array = split(' ', $llc_option_macro);
    if ( $griffin_flow ) { push(@additional_llc_args, qw(--grif)); }


    # DSPBA backend needs to know the device that we're targeting
    if ( $griffin_flow ) { 
      my $grif_device;
      if ( $qii_device ) {
        $grif_device = $qii_device;
      } else {
        $grif_device = get_default_qii_device();
      }
      push(@additional_llc_args, qw(--device));
      push(@additional_llc_args, qq($grif_device) );

      # DSPBA backend needs to know the device family - Bugz:309237 tracks extraction of this info from the part number in DSPBA
      # Device is defined by this point - even if it was set to the default.
      # Query Quartus to get the device family`
      mydie("Internal error: Device unexpectedly not set") if (!defined $grif_device);
      my $grif_family = device_get_family_no_normalization($grif_device); 
      push(@additional_llc_args, qw(--family));
      push(@additional_llc_args, "\"".$grif_family."\"" );

      # DSPBA backend needs to know the device speed grade - Bugz:309237 tracks extraction of this info from the part number in DSPBA
      # The device is now defined, even if we've chosen the default automatically.
      # Query Quartus to get the device speed grade.
      mydie("Internal error: Device unexpectedly not set") if (!defined $grif_device);
      my $grif_speedgrade = device_get_speedgrade( $grif_device );
      push(@additional_llc_args, qw(--speed_grade));
      push(@additional_llc_args, qq($grif_speedgrade) );
    }

    if ( $griffin_folding_flow ) { push(@additional_llc_args, qw(--fold)); }

    @cmd_list = (
        $llc_exe,
        @llc_option_macro_array,
        qw(-HLS),
        qw(--board hls.xml),
        @additional_llc_args,
        $final,
        '-o',
        get_name_core($project_name).'.v' );

    mysystem_full({'title' => 'LLC', 'time' => 1, 'time-label' => 'llc'}, @cmd_list) == 0 or mydie();


    my $xml_file = get_name_core(${project_name}).'.bc.xml';

    mysystem_full(
      {'title' => 'System Integration'},
      ($sysinteg_exe, @additional_sysinteg_args,'--hls', 'hls.xml', $xml_file )) == 0 or mydie();


    my @components = get_generated_components();
    my $ipgen_result = create_qsys_components(@components);
    mydie("Failed to generate QIP files\n") if ($ipgen_result);

    chdir $orig_dir or mydie("Can't change into dir $orig_dir: $!\n");

    #Cleanup everything but final bc
    push @cleanup_list, acl::File::simple_glob( $g_work_dir."/*.*.bc" );
    push @cleanup_list, $g_work_dir.'interfacedesc.txt';

    save_and_report(${final});
}

sub link_IR (@) {
    my ($resfile,@list) = @_;
    my $full_name = ${g_work_dir}.'/'.${resfile};
    # Link with standard library.
    @cmd_list = (
      $link_exe,
      @list,
      '-o',$full_name );

    mysystem_full( {'title' => 'Link IR'}, @cmd_list) == 0 or mydie();

    disassemble($full_name);
}

sub link_x86 ($) {
    my $output_name = shift ;

    print "Linking x86 objects\n" if $verbose;
    
    @cmd_list = (
      $clang_exe,
      ($verbose>2)?'-v':'',
      "-D__ALTERA_TYPE__=$macro_type_string",
      @object_list,
      '-o',
      $executable,
      @linkflags,
      '-lhls_emul'
      );
    
    mysystem_full( {'title' => 'Emulator Link'}, @cmd_list) == 0 or mydie();

    return;
}

sub get_generated_components() {

    # read the comma-separated list of components from a file
    my $project_bc_xml_filename = get_name_core(${project_name}).'.bc.xml';
    my $BC_XML_FILE;
    open (BC_XML_FILE, "<${project_bc_xml_filename}") or mydie "Couldn't open ${project_bc_xml_filename} for read!\n";
    my @dut_array;
    while(my $var =<BC_XML_FILE>) {
      if ($var =~ /<KERNEL name="(.*)" filename/) {
          push(@dut_array,$1); 
    }
    }
    close BC_XML_FILE;

    return @dut_array;
}

sub hls_sim_generate_verilog($) {
    my ($HLS_FILENAME_NOEXT) = $_;
    if (!$HLS_FILENAME_NOEXT) {
      $HLS_FILENAME_NOEXT='a';
    }

    print "Generating cosimulation support\n" if $verbose;

    chdir $g_work_dir or mydie("Can't change into dir $g_work_dir: $!\n");

    my @dut_array = get_generated_components();
    # finally, recreate the comma-separated string from the array with unique elements
    my $DUT_LIST  = join(',',@dut_array);

    print "Generating simulation files for components: $DUT_LIST in $HLS_FILENAME_NOEXT\n" if $verbose;

    if (!defined($HLS_FILENAME_NOEXT) or !defined($DUT_LIST)) {
      mydie("Error: Pass the input file name and component names into the hls_sim_generate_verilog function\n");
    }

    my $HLS_GEN_FILES_DIR = $HLS_FILENAME_NOEXT;
    my $SEARCH_PATH = acl::Env::sdk_root()."/ip/,.,\$"; # no space between paths!

    # Setup file path names
    my $HLS_GEN_FILES_SIM_DIR = './sim';
    my $HLS_QSYS_SIM_NOEXT    = $HLS_FILENAME_NOEXT.'_sim';

    # Because the qsys-script tcl cannot accept arguments, 
    # pass them in using the --cmd option, which runs a tcl cmd
    my $init_var_tcl_cmd = "set sim_qsys $HLS_FILENAME_NOEXT; set component_list $DUT_LIST;";

    # Create the simulation directory  
    my $sim_dir_abs_path = acl::File::abs_path("./$HLS_GEN_FILES_SIM_DIR");
    print "HLS simulation directory: $sim_dir_abs_path.\n" if $verbose;
    acl::File::make_path($HLS_GEN_FILES_SIM_DIR) or mydie("Can't create simulation directory $sim_dir_abs_path: $!");

    my $gen_qsys_tcl = acl::Env::sdk_root()."/share/lib/tcl/hls_sim_generate_qsys.tcl";

    # Run hls_sim_generate_qsys.tcl to generate the .qsys file for the simulation system 
    mysystem_full(
      {'stdout' => $project_log,'stderr' => $project_log, 'title' => 'gen_qsys'},
      'qsys-script --search-path='.$SEARCH_PATH.' --script='.$gen_qsys_tcl.' --cmd="'.$init_var_tcl_cmd.'"')  == 0 or mydie();

    # Move the .qsys we just made to the sim dir
    mysystem_full({'stdout' => $project_log, , 'stderr' => $project_log, 'title' => 'move qsys'},"mv $HLS_QSYS_SIM_NOEXT.qsys $HLS_GEN_FILES_SIM_DIR") == 0 or mydie();

    # Generate the verilog for the simulation system
    @cmd_list = ('qsys-generate',
      '--search-path='.$SEARCH_PATH,
      '--simulation=VERILOG',
      '--output-directory='.$HLS_GEN_FILES_SIM_DIR,
      '--family='.$family,
      '--part='.$qii_device,
      $HLS_GEN_FILES_SIM_DIR.'/'.$HLS_QSYS_SIM_NOEXT.'.qsys');

    mysystem_full(
      {'stdout' => $project_log, 'stderr' => $project_log, 'title' => 'generate verilog'}, 
      @cmd_list)  == 0 or mydie();

    # Generate simulation scripts
    @cmd_list = ('ip-make-simscript',
      '--compile-to-work',
      "-spd=$HLS_GEN_FILES_SIM_DIR/$HLS_QSYS_SIM_NOEXT.spd",
      "--output-directory=$HLS_GEN_FILES_SIM_DIR");
    
    mysystem_full(
      {'stdout' => $project_log, 'stderr' => $project_log, 'title' => 'generate simulation script'},
      @cmd_list) == 0 or mydie();

    chdir $orig_dir or mydie("Can't change into dir $orig_dir: $!\n");

    # Generate scripts that the user can run to perform the actual simulation.
    my $qsys_dir = get_qsys_output_dir("SIM_VERILOG");
    generate_simulation_scripts($HLS_FILENAME_NOEXT, "sim/$qsys_dir", $g_work_dir);
}


# This module creates a file:
# Moved everything into one file to deal with run time parameters, i.e. execution directory vs scripts placement.
#Previous do scripts are rewritten to strings that gets put into the run script
#Also perl driver in project directory is gone.
#  - compile_do      (the string run by the compilation phase, in the output dir)
#  - simulate_do     (the string run by the simulation phase, in the output dir)
#  - <source>        (the executable top-level simulation script, in the top-level dir)
sub generate_simulation_scripts($) {
    my ($HLS_QSYS_SIM_NOEXT, $HLS_GEN_FILES_SIM_DIR, $g_work_dir) = @_;

    # Working directories
    my $projdir = acl::File::mybasename($g_work_dir);
    my $outputdir = acl::File::mydirname($g_work_dir);
    my $simscriptdir = $HLS_GEN_FILES_SIM_DIR.'/mentor';
    # Script filenames
    my $fname_compilescript = $simscriptdir.'/msim_compile.tcl';
    my $fname_runscript = $simscriptdir.'/msim_run.tcl';
    my $fname_msimsetup = $simscriptdir.'/msim_setup.tcl';
    my $fname_svlib = $HLS_QSYS_SIM_NOEXT.'_sim';
    my $fname_msimini = 'modelsim.ini';
    my $fname_exe_com_script = 'compile.sh';

    # Other variables
    my $top_module = $HLS_QSYS_SIM_NOEXT.'_sim';

    # Generate the modelsim compilation script
    my $COMPILE_SCRIPT_FILE;
    open(COMPILE_SCRIPT_FILE, ">", "$g_work_dir/$fname_compilescript") or mydie "Couldn't open $g_work_dir/$fname_compilescript for write!\n";
    print COMPILE_SCRIPT_FILE "onerror {abort all; exit -code 1;}\n";
    print COMPILE_SCRIPT_FILE "set QSYS_SIMDIR \${scripthome}/$projdir/$simscriptdir/..\n";
    print COMPILE_SCRIPT_FILE "source \${scripthome}/$projdir/$fname_msimsetup\n";
    print COMPILE_SCRIPT_FILE "set ELAB_OPTIONS \"+nowarnTFMPC";
    print COMPILE_SCRIPT_FILE ($cosim_debug ? " -voptargs=+acc\"\n"
                                            : "\"\n");
    print COMPILE_SCRIPT_FILE "dev_com\n";
    print COMPILE_SCRIPT_FILE "com\n";
    print COMPILE_SCRIPT_FILE "elab\n";
    print COMPILE_SCRIPT_FILE "exit -code 0\n";
    close(COMPILE_SCRIPT_FILE);

    # Generate the run script
    my $RUN_SCRIPT_FILE;
    open(RUN_SCRIPT_FILE, ">", "$g_work_dir/$fname_runscript") or mydie "Couldn't open $g_work_dir/$fname_runscript for write!\n";
    print RUN_SCRIPT_FILE "onerror {abort all; exit -code 1;}\n";
    print RUN_SCRIPT_FILE "set QSYS_SIMDIR \${scripthome}/$projdir/$simscriptdir/..\n";
    print RUN_SCRIPT_FILE "source \${scripthome}/$projdir/$fname_msimsetup\n";
    print RUN_SCRIPT_FILE "# Suppress warnings from the std arithmetic libraries\n";
    print RUN_SCRIPT_FILE "set StdArithNoWarnings 1\n";
    print RUN_SCRIPT_FILE "set ELAB_OPTIONS \"+nowarnTFMPC -dpioutoftheblue 1 -sv_lib \${scripthome}/$projdir/$fname_svlib";
    print RUN_SCRIPT_FILE ($cosim_debug ? " -voptargs=+acc\"\n"
                                        : "\"\n");
    print RUN_SCRIPT_FILE "elab\n";
    print RUN_SCRIPT_FILE "log -r *\n" if $cosim_debug;
    print RUN_SCRIPT_FILE "run -all\n";
    print RUN_SCRIPT_FILE "exit -code 0\n";
    close(RUN_SCRIPT_FILE);

    # Generate the executable script
    my $EXE_FILE;
    open(EXE_FILE, '>', $executable) or die "Could not open file '$executable' $!";
    print EXE_FILE "#!/bin/sh\n";
    print EXE_FILE "\n";
    print EXE_FILE "# Identify the directory to run from\n";
    print EXE_FILE "scripthome=\$(dirname \$0)\n";
    print EXE_FILE "# Run the testbench\n";
    print EXE_FILE "vsim -batch -modelsimini \${scripthome}/$projdir/$fname_msimini -nostdout -keepstdout -l transcript.log -stats=none -do \"set scripthome \${scripthome}; do \${scripthome}/$projdir/$fname_runscript\"\n";
    print EXE_FILE "if [ \$? -ne 0 ]; then\n";
    print EXE_FILE "  >&2 echo \"ModelSim simulation failed.  See transcript.log for more information.\"\n";
    print EXE_FILE "  exit 1\n";
    print EXE_FILE "fi\n";
    print EXE_FILE "exit 0\n";
    close(EXE_FILE);
    system("chmod +x $executable"); 

    # Generate a script that we'll call to compile the design
    my $EXE_COM_FILE;
    open(EXE_COM_FILE, '>', "$g_work_dir/$fname_exe_com_script") or die "Could not open file '$g_work_dir/$fname_exe_com_script' $!";
    print EXE_COM_FILE "#!/bin/sh\n";
    print EXE_COM_FILE "\n";
    print EXE_COM_FILE "# Identify the directory to run from\n";
    print EXE_COM_FILE "scripthome=\$(dirname \$0)/..\n";
    print EXE_COM_FILE "# Compile and elaborate the testbench\n";
    print EXE_COM_FILE "vsim -batch -modelsimini \${scripthome}/$projdir/$fname_msimini -do \"set scripthome \${scripthome}; do \${scripthome}/$projdir/$fname_compilescript\"\n";
    print EXE_COM_FILE "exit \$?\n";
    close(EXE_COM_FILE);
    system("chmod +x $g_work_dir/$fname_exe_com_script"); 

    # Modelsim maps its libraries to ./libraries - to keep paths consistent we'd like to map them to
    # scripthome/g_work_dir/libraries
    my $MSIM_SETUP_FILE;
    open(MSIM_SETUP_FILE, "<", "$g_work_dir/$fname_msimsetup") || die "Could not open $g_work_dir/$fname_msimsetup for read.";
    my @lines = <MSIM_SETUP_FILE>;
    close(MSIM_SETUP_FILE);
    foreach(@lines) {
      s^\./libraries/^\${scripthome}/$projdir/libraries/^g;
    }
    open(MSIM_SETUP_FILE, ">", "$g_work_dir/$fname_msimsetup") || die "Could not open $g_work_dir/$fname_msimsetup for write.";
    print MSIM_SETUP_FILE @lines;
    close(MSIM_SETUP_FILE);

    # Generate the common modelsim.ini file
    @cmd_list = ('vmap','-c');
    $return_status = mysystem_full({'stdout' => $project_log,'stderr' => $project_log,
                                    'title' => 'Capture default modelsim.ini'}, 
                                    @cmd_list);
    # Missing ModelSim in environment is a common problem, let's give a special message
    if($return_status != 0) {
        mydie("Error accessing ModelSim.  Please ensure you have a valid ModelSim installation on your path.\n" .
              "       Check your ModelSim installation with \"vmap -version\" \n"); 
    } 
    acl::File::copy('modelsim.ini', "$g_work_dir/$fname_msimini");
    remove_named_files('modelsim.ini');

    # Compile the cosim design
=begin comment
    @cmd_list = ('vsim',
      "-batch",
      "-modelsimini",
      "$g_work_dir/$fname_msimini",
      "-do",
      "set scripthome $outputdir; do $g_work_dir/$fname_compilescript");
=cut
    @cmd_list = ("$g_work_dir/$fname_exe_com_script");
    $return_status = mysystem_full(
      {'stdout' => $project_log,'stderr' => $project_log,
       'title' => 'Elaborate cosim testbench.'},
      @cmd_list);
    # Missing license is such a common problem, let's give a special message
    if($return_status == 4) {
      mydie("Missing simulator license.  Either:\n" .
            "  1) Ensure you have a valid ModelSim license\n" .
            "  2) Use the --rtl-only flag to skip the cosim flow\n");
    } elsif($return_status != 0) {
      mydie("Cosim testbench elaboration failed.\n");
    }
}

sub gen_qsys_script(@) {
    my @components = @_;


    foreach (@components) {
        # Generate the tcl for the system
        open(my $qsys_script, '>', "$_.tcl") or die "Could not open file '$_.tcl' $!";

        print $qsys_script <<SCRIPT;
package require -exact qsys 15.0

# create the system with the name

create_system $_

# set project properties

set_project_property HIDE_FROM_IP_CATALOG false
set_project_property DEVICE_FAMILY "${family}"
set_project_property DEVICE "${qii_device}"

# adding the ip for which the variation has to be created for

add_instance ${_}_internal_inst ${_}_internal

# auto export all the interfaces

# this will make the exported ports to have the same port names as that of altera_pcie_a10_hip

set_instance_property ${_}_internal_inst AUTO_EXPORT true

# save the Qsys file

save_system "$_.qsys"
SCRIPT
        close $qsys_script;
    }

}

sub run_qsys_script(@) {
    my @components = @_;

    foreach (@components) {
        # Generate the verilog for the simulation system
        @cmd_list = ('qsys-script',
                "--script=$_.tcl");

        mysystem_full(
            {'stdout' => $project_log, 'stderr' => $project_log, 'title' => 'generate component QSYS script'}, 
            @cmd_list) == 0 or mydie();
    }
}

sub post_process_qsys_files(@) {
    my @components = @_;

    my $return_status = 0;

    foreach (@components) {

        # Read in the current QSYS file
        open (FILE, "<${_}.qsys") or die "Can't open ${_}.qsys for read";
        my @lines;
        while (my $line = <FILE>) {
                # this organizes the components in the IP catalog under the same HLS/ directory
                $line =~ s/categories=""/categories="HLS"/g;
                push(@lines, $line);
        }
        close(FILE);

        # Write out the modified QSYS file
        open (OFH, ">${_}.qsys") or die "Can't open ${_}.qsys for write";
        foreach my $line (@lines) {
                print OFH $line;
        }
        close(OFH);

    }

    return $return_status;
}

sub run_qsys_generate($@) {
    my ($target, @components) = @_;

    foreach (@components) {
        # Generate the verilog for the simulation system
        @cmd_list = ('qsys-generate',
                "--$target=VERILOG",
                "--family=$family",
                '--part='.$qii_device,
                $_ . ".qsys");

        mysystem_full(
            {'stdout' => $project_log, 'stderr' => $project_log, 'title' => 'generate verilog and qip for QII compile'}, 
            @cmd_list) == 0 or mydie();
    }

}

sub create_qsys_components(@) {
    my @components = @_;

    gen_qsys_script(@components);
    run_qsys_script(@components);
    post_process_qsys_files(@components);
    run_qsys_generate("synthesis", @components);
}

sub get_qsys_output_dir($) {
   my ($target) = @_;

   my $dir = ($target eq "SIM_VERILOG") ? "simulation" : "synthesis";

   if ($family eq "ARRIA10") {
      $dir = ($target eq "SIM_VERILOG")   ? "sim"   :
             ($target eq "SYNTH_VERILOG") ? "synth" :
                                            "";
   }

   return $dir;
}

sub generate_top_level_qii_verilog($@) {
    my ($qii_project_name, @components) = @_;

    my %clock2x_used;
    my %component_portlists;

    my $qsys_dir = get_qsys_output_dir("SYNTH_VERILOG");

    foreach (@components) {
            #read in component module from file and parse for portlist
            open (FILE, "<../${_}/${qsys_dir}/${_}.v") or die "Can't open ../${_}/${qsys_dir}/${_}.v for read";

            #parse for portlist
            my $in_module = 0;
            while (my $line = <FILE>) {
                if ($in_module) {
                    #this regex only picks up legal verilog identifiers, not escaped identifiers
                    if ($line =~ m/^\s*(input|output)\s+wire\s+(\[\d+:\d+\])?\s*([a-zA-Z_0-9\$]+),?\s*/) {
                        push(@{$component_portlists{$_}}, {'dir' => $1, 'range' => $2, 'name' => $3});
                        if ($3 eq "clock2x") {
                            push(@{$clock2x_used{$_}}, 1);
                        }
                    } elsif ($line =~ m/^\s*(input|output)\s+([a-zA-Z_0-9\$]+)\s+([a-zA-Z_0-9\$]+),?\s*/){
                        # handle structs
                        push(@{$component_portlists{$_}}, {'dir' => $1, 'range' => "[\$bits($2)-1:0]", 'name' => $3});
                    } elsif ($line =~ m/\s*endmodule\s*/){
                        $in_module = 0;
                    }
                } elsif (not $in_module and ($line =~ m/^\s*module\s+${_}\s/)) {
                    $in_module = 1;
                }
            }
            close(FILE);
    }

    #output top level
    open (OFH, ">${qii_project_name}.v") or die "Can't open ${qii_project_name}.v for write";
    print OFH "module ${qii_project_name} (\n";

    #ports
    print OFH "\t  input logic resetn\n";
    print OFH "\t, input logic clock\n";
    if (scalar keys %clock2x_used) {
        print OFH "\t, input logic clock2x\n";
    }
    foreach (@components) {
        my @portlist = @{$component_portlists{$_}};
        foreach my $port (@portlist) {

            #skip clocks and reset
            my $port_name = $port->{'name'};
            if ($port_name eq "resetn" or $port_name eq "clock" or $port_name eq "clock2x") {
                next;
            }

            #component ports
            print OFH "\t, $port->{'dir'} logic $port->{'range'} ${_}_$port->{'name'}\n";
        }
    }
    print OFH "\t);\n\n";

    if ($qii_io_regs) {
        #declare registers
        foreach (@components) {
            my @portlist = @{$component_portlists{$_}};
            foreach my $port (@portlist) {
                my $port_name = $port->{'name'};

                #skip clocks and reset
                if ($port_name eq "resetn" or $port_name eq "clock" or $port_name eq "clock2x") {
                    next;
                }

                print OFH "\tlogic $port->{'range'} ${_}_${port_name}_reg;\n";
            }
        }

        #wire registers
        foreach (@components) {
            my @portlist = @{$component_portlists{$_}};

            print OFH "\n\n\talways @(posedge clock) begin\n";
            foreach my $port (@portlist) {
                my $port_name = "$port->{'name'}";

                #skip clocks and reset
                if ($port_name eq "resetn" or $port_name eq "clock" or $port_name eq "clock2x") {
                    next;
                }

                $port_name = "${_}_${port_name}";
                if ($port->{'dir'} eq "input") {
                    print OFH "\t\t${port_name}_reg <= ${port_name};\n";
                } else {
                    print OFH "\t\t${port_name} <= ${port_name}_reg;\n";
                }
            }
            print OFH "\tend\n";
        }
    }

    #component instances
    my $comp_idx = 0;
    foreach (@components) {
        my @portlist = @{$component_portlists{$_}};

        print OFH "\n\n\t${_} hls_component_dut_inst_${comp_idx} (\n";
        print OFH "\t\t  .resetn(resetn)\n";
        print OFH "\t\t, .clock(clock)\n";
        if (exists $clock2x_used{$_}) {
            print OFH "\t\t, .clock2x(clock2x)\n";
        }

        foreach my $port (@portlist) {

            my $port_name = $port->{'name'};

            #skip clocks and reset
            if ($port_name eq "resetn" or $port_name eq "clock" or $port_name eq "clock2x") {
                next;
            }

            my $reg_name_suffix = $qii_io_regs ? "_reg" : "";
            my $reg_name = "${_}_${port_name}${reg_name_suffix}";
            print OFH "\t\t, .${port_name}(${reg_name})\n";
        }
        print OFH "\t);\n\n";
        $comp_idx = $comp_idx + 1
    }

    print OFH "\n\nendmodule\n";
    close(OFH);

    return scalar keys %clock2x_used;

}

sub generate_qsf($@) {
    my ($qii_project_name, @components) = @_;

    open (OUT_QSF, ">${qii_project_name}.qsf") or die;

    print OUT_QSF "set_global_assignment -name FAMILY \\\"${family}\\\"\n";
    print OUT_QSF "set_global_assignment -name DEVICE ${qii_device}\n";
    print OUT_QSF "set_global_assignment -name TOP_LEVEL_ENTITY ${qii_project_name}\n";
    print OUT_QSF "set_global_assignment -name SDC_FILE ${qii_project_name}.sdc\n";

    if ($qii_vpins) {
        my $qii_vpin_tcl = acl::Env::sdk_root()."/share/lib/tcl/hls_qii_compile_create_vpins.tcl";
        print OUT_QSF "set_global_assignment -name POST_MODULE_SCRIPT_FILE \\\"quartus_sh:${qii_vpin_tcl}\\\"\n";
    }

    # add call to parsing script after STA is run
    my $qii_rpt_tcl = acl::Env::sdk_root()."/share/lib/tcl/hls_qii_compile_report.tcl";
    print OUT_QSF "set_global_assignment -name POST_FLOW_SCRIPT_FILE \\\"quartus_sh:${qii_rpt_tcl}\\\"\n";

    # add component QIP files to project
    my $qsys_dir = get_qsys_output_dir("QIP");
    foreach (@components) {
        print OUT_QSF "set_global_assignment -name QIP_FILE ../$_/${qsys_dir}/$_.qip\n";
    }

    # add generated top level verilog file to project
    print OUT_QSF "set_global_assignment -name SYSTEMVERILOG_FILE ${qii_project_name}.v\n";

    my $comp_idx = 0;
    print OUT_QSF "\nset_global_assignment -name PARTITION_NETLIST_TYPE SOURCE -section_id component_partition\n";
    print OUT_QSF "set_global_assignment -name PARTITION_FITTER_PRESERVATION_LEVEL PLACEMENT_AND_ROUTING -section_id component_partition\n";
    foreach (@components) {
        print OUT_QSF "\nset_instance_assignment -name PARTITION_HIERARCHY component -to \"${_}:hls_component_dut_inst_${comp_idx}\" -section_id component_partition";
        $comp_idx = $comp_idx + 1;
    }

    if (defined $qii_seed ) {
        print OUT_QSF "\nset_global_assignment -name SEED $qii_seed";
    }

    close(OUT_QSF);
}

sub generate_sdc($$) {
  my ($qii_project_name, $clock2x_used) = @_;


  open (OUT_SDC, ">${qii_project_name}.sdc") or die;

  print OUT_SDC "create_clock -period 1 clock\n";                                                                                                          
  if ($clock2x_used) {                                                                                                                                        
    print OUT_SDC "create_clock -period 0.5 clock2x\n";                                                                                           
  }                                                                                                                                                           

  close (OUT_SDC);
}

sub generate_quartus_ini() {

  open(OUT_INI, ">quartus.ini") or die;

  #temporary work around for A10 compiles
  if ($family eq "ARRIA10") {
    print OUT_INI "a10_iopll_es_fix=off\n";
  }

  close(OUT_INI);
}

sub generate_qii_project {

    # change to the working directory
    chdir $g_work_dir or mydie("Can't change into dir $g_work_dir: $!\n");

    my $qii_project_name = "qii_compile_top";

    my @components = get_generated_components();

    if (not -d "qii") {
        mkdir "qii" or mydie("Can't make dir qii: $!\n");
    }
    chdir "qii" or mydie("Can't change into dir qii: $!\n");

    my $clock2x_used = generate_top_level_qii_verilog($qii_project_name, @components);
    generate_qsf($qii_project_name, @components);
    generate_sdc($qii_project_name, $clock2x_used);

    generate_quartus_ini();

    # change back to original directory
    chdir $orig_dir or mydie("Can't change into dir $orig_dir: $!\n");

    return $qii_project_name;
}

sub compile_qii_project($) {
    my ($qii_project_name) = @_;

    # change to the working directory
    chdir $g_work_dir."/qii" or mydie("Can't change into dir $g_work_dir/qii: $!\n");

    @cmd_list = ('quartus_sh',
            #'--search-path='.$SEARCH_PATH,
            "--flow",
            "compile",
            "$qii_project_name");

    mysystem_full(
        {'stdout' => $project_log, 'stderr' => $project_log, 'title' => 'run QII compile'}, 
        @cmd_list) == 0 or mydie();

    # change back to original directory
    chdir $orig_dir or mydie("Can't change into dir $orig_dir: $!\n");

    return $return_status;
}

sub parse_qii_compile_results($) {
    my ($qii_project_name) = @_;

    # change to the working directory
    chdir $g_work_dir or mydie("Can't change into dir $g_work_dir: $!\n");
    
    # change back to original directory
    chdir $orig_dir or mydie("Can't change into dir $orig_dir: $!\n");

}

sub open_time_log_file {
  # Process $time_log. If defined, then treat it as a file name 
  # (including "-", which is stdout).
  # Code copied from aoc.pl
  if ($time_log) {
    my $fh;
    if ($time_log ne "-") {
      # Overwrite the log if it exists
      open ($fh, '>', $time_log) or mydie ("Couldn't open $time_log for time output.");
    } else {
      # Use STDOUT.
      open ($fh, '>&', \*STDOUT) or mydie ("Couldn't open stdout for time output.");
    }
    # From this point forward, $time_log is now a file handle!
    $time_log = $fh;
  }
}

sub run_quartus_compile {
    print "Run Quartus\n" if $verbose;

    my $qii_project_name = generate_qii_project();
    compile_qii_project($qii_project_name);
    parse_qii_compile_results($qii_project_name);
}

sub main {
    parse_args();

    # Default to emulator
    if ( not $emulator_flow and not $simulator_flow ) {$emulator_flow = 1;}

    if ( $emulator_flow ) {$macro_type_string = "NONE";}
    else                  {$macro_type_string = "VERILOG";}

    open_time_log_file();

    # Process all source files one by one
    while ($#source_list >= 0) {
      my $source_file = shift @source_list;
      my $object_name = get_name_core($source_file).'.o';

      if ( $project_name && $object_only_flow_modifier) {
        # -c, so -o name applies to object file, don't add .o
        $object_name = $project_name;
      } 

      if ( $emulator_flow ) {
        emulator_compile($source_file, $object_name);
      } else {
        fpga_parse($source_file, $object_name);
        if (!$RTL_only_flow_modifier && !$soft_ip_c_flow_modifier) {
          testbench_parse($source_file, $object_name);
        }
      }
    }

    if ($object_only_flow_modifier) { myexit('Object generation'); }

    # Need to be here setup might redefine $project_name
    $executable=($project_name)?$project_name:'a.out';

    setup_linkstep(); #unpack objects and setup project directory

    # Now do the 'real' compiles depend link step, wich includes llvm cmpile for
    # testbench and components
    if ($#fpga_IR_list >= 0) {
      preprocess(); # Find board
      generate_fpga(@fpga_IR_list);
    }

    if ($qii_flow) {
      run_quartus_compile();
      myexit("");
    }

    if ($RTL_only_flow_modifier) { myexit('RTL Only'); }

    if ($#tb_IR_list >= 0) {
      my $merged_file='tb.merge.bc';
      link_IR( $merged_file, @tb_IR_list);
      generate_testbench( $merged_file );
    }

    if ( $#object_list < 0) {
      hls_sim_generate_verilog($project_name);
    }   

    if ($#object_list >= 0) {
      link_x86($executable);
    }

    if ($time_log) {
      close ($time_log);
    }

    myexit("");
}

main;
