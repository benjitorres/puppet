class ocf_desktop::xsession(
  Float[1.0, 3.0] $scale = 1.0
) {
  $staff_only = lookup('staff_only')

  require ocf_desktop::packages
  include ocf_desktop::kde
  include ocf_desktop::lockkill

  # Scaling variables
  $dpi = round($scale * 96)
  # These sizes are specific to the cursor theme (currently, Breeze)
  if $scale < 1.5 {
    $cursor_size = 24
  } elsif $scale < 2 {
    $cursor_size = 36
  } else {
    $cursor_size = 48
  }
  $panel_height = round($scale * 48)

  # Xsession configuration
  file {
    # custom Xsession script to populate desktop
    '/etc/X11/Xsession.d/95ocf':
      source  => 'puppet:///modules/ocf_desktop/xsession/Xsession',
      require => File['/opt/share/xsession'];
    # printing and other notification script daemon
    '/opt/share/puppet/notify':
      mode   => '0755',
      source => 'puppet:///modules/ocf_desktop/xsession/notify';
    # script for warning users when the lab is about to close
    '/opt/share/puppet/lab-close-notify':
      mode   => '0755',
      source => 'puppet:///modules/ocf_desktop/xsession/lab-close-notify';
    # script to notify users of print job status
    '/opt/share/puppet/print-notify-listener':
      mode   => '0755',
      source => 'puppet:///modules/ocf_desktop/xsession/print-notify-listener';
    '/opt/share/puppet/print-notify-handler':
      mode   => '0755',
      source => 'puppet:///modules/ocf_desktop/xsession/print-notify-handler';
    # script to tile multiple displays
    '/usr/local/bin/fix-displays':
      mode   => '0755',
      source => 'puppet:///modules/ocf_desktop/xsession/fix-displays';
    # script to fix audio on login
    '/usr/local/bin/fix-audio':
      mode   => '0755',
      source => 'puppet:///modules/ocf_desktop/xsession/fix-audio';
    # script for paper stats on panel
    '/usr/local/bin/paper-genmon':
      mode    => '0755',
      source  => 'puppet:///modules/ocf_desktop/xsession/paper-genmon',
      require => File['/opt/share/xsession/icons'];
    # list of possible xsessions
    '/usr/share/xsessions':
      ensure  => directory,
      source  => 'puppet:///modules/ocf_desktop/xsession/xsessions',
      recurse => true,
      force   => true,
      backup  => false;
    '/usr/share/xsessions/lightdm-xsession.desktop':
      ensure => absent;
    '/opt/share/xsession':
      ensure  => directory;
    '/opt/share/xsession/images':
      source  => 'puppet:///modules/ocf_desktop/xsession/images/',
      recurse => true,
      purge   => true;
    '/opt/share/xsession/icons':
      source  => 'puppet:///modules/ocf_desktop/xsession/icons/',
      recurse => true,
      purge   => true;
  }

  file { '/opt/share/wallpaper':
    ensure  => link,
    target  => '/opt/share/xsession/images/background.png',
    require => File['/opt/share/xsession/images'];
  }

  # select which login background to use
  $login_screen = $staff_only ? {
    true    => 'login-staff.png',
    default => 'login.png',
  }

  file { '/opt/share/login':
    ensure  => link,
    target  => "/opt/share/xsession/images/${login_screen}",
    require => File['/opt/share/xsession/images'];
  }

  # lightdm configuration
  # install lightdm as login manager with minimal bloat
  file {
    '/etc/lightdm/lightdm.conf':
      source  => 'puppet:///modules/ocf_desktop/xsession/lightdm/lightdm.conf';
    '/etc/lightdm/lightdm-gtk-greeter.conf':
      content => template('ocf_desktop/xsession/lightdm-gtk-greeter.conf.erb');
    '/etc/X11/default-display-manager':
      content => "/usr/sbin/lightdm\n";
    '/etc/lightdm/session-setup':
      mode   => '0755',
      source => 'puppet:///modules/ocf_desktop/xsession/lightdm/session-setup';
    # kill child processes on logout
    '/etc/lightdm/session-cleanup':
      mode   => '0755',
      source => 'puppet:///modules/ocf_desktop/xsession/lightdm/session-cleanup';
  }

  # overwrite greeter strings with OCF ones
  package {'gettext':;}

  $po = $staff_only ? {
    true    => 'lightdm-gtk-greeter-staff.po',
    default => 'lightdm-gtk-greeter.po',
  }

  file { "/opt/share/xsession/${po}":
    source  => "puppet:///modules/ocf_desktop/xsession/lightdm/${po}";
  }

  exec { 'lightdm-greeter-compile-po':
    command     => "msgfmt -o /usr/share/locale/en_US/LC_MESSAGES/lightdm-gtk-greeter.mo \
                    /opt/share/xsession/${po}",
    subscribe   => File["/opt/share/xsession/${po}"],
    refreshonly => true,
    require     => Package['lightdm-gtk-greeter', 'gettext'];
  }

  # add pam_trimspaces to lightdm PAM stack
  augeas { 'lightdm-pam_trimspaces':
    context => '/files/etc/pam.d/lightdm',
    changes => [
      'ins #comment after #comment[1]',
      'set #comment[2] "Strip leading and trailing space from username"',
      'ins 01 after #comment[2]',
      'set 01/type auth',
      'set 01/control requisite',
      'set 01/module pam_trimspaces.so',
    ],
    onlyif  => 'match *[module = "pam_trimspaces.so"] size == 0';
  }

  # use ocf logo on login screen
  if $::lsbdistcodename == 'bullseye' {
    file {
      ['/usr/share/icons/Adwaita', '/usr/share/icons/Adwaita/512x512', '/usr/share/icons/Adwaita/512x512/status']:
        ensure => directory;
      '/usr/share/icons/Adwaita/512x512/status/avatar-default.png':
        ensure  => link,
        target  => '/opt/share/xsession/images/ocf-color-512.png',
        require => File['/opt/share/xsession/images'];
    }
  } else {
    file {
      ['/usr/share/icons/Adwaita', '/usr/share/icons/Adwaita/256x256', '/usr/share/icons/Adwaita/256x256/status']:
        ensure => directory;
      '/usr/share/icons/Adwaita/256x256/status/avatar-default.png':
        ensure  => link,
        target  => '/opt/share/xsession/images/ocf-color-256.png',
        require => File['/opt/share/xsession/images'];
    }
  }


  # polkit configuration
  file {
    # restrict polkit actions
    '/etc/polkit-1/localauthority/90-mandatory.d/99-ocf.pkla':
      #source => 'puppet:///modules/ocf_desktop/xsession/polkit/99-ocf.pkla',
      # Workaround for bug causing polkit rules to be ignored - merge all
      # rules into one file so that they are not ignored
      content => join([
        file('ocf_desktop/xsession/polkit/99-ocf.pkla'),
        file('ocf_desktop/lockkill/policy.pkla'),
      ], "\n"),
    ;
    # use ocfroot group for polkit admin auth
    '/etc/polkit-1/localauthority.conf.d/99-ocf.conf':
      source => 'puppet:///modules/ocf_desktop/xsession/polkit/99-ocf.conf',
    ;
  }

  file {
    # copy skel files
    '/etc/skel/.config':
      ensure  => directory,
      source  => 'puppet:///modules/ocf_desktop/skel/config',
      recurse => true;
    '/etc/skel/.local':
      ensure  => directory,
      source  => 'puppet:///modules/ocf_desktop/skel/local',
      recurse => true;
    '/etc/skel/Desktop':
      ensure  => directory,
      source  => 'puppet:///modules/ocf_desktop/skel/Desktop',
      mode    => '0755',
      recurse => true;
  }

  # Templated config files (scale-dependent)
  file {
    '/etc/skel/.config/kdeglobals':
      content   => template('ocf_desktop/skel/config/kdeglobals.erb');
    '/etc/skel/.config/kcmfonts':
      content   => template('ocf_desktop/skel/config/kcmfonts.erb');
    '/etc/skel/.config/kcminputrc':
      content   => template('ocf_desktop/skel/config/kcminputrc.erb');
    '/etc/skel/.config/plasmashellrc':
      content   => template('ocf_desktop/skel/config/plasmashellrc.erb');
  }

  # Fix desktop icon text color
  file {
    '/etc/skel/.gtkrc-2.0':
      source => 'puppet:///modules/ocf_desktop/skel/.gtkrc-2.0';
  }

  # disable user switching and screen locking (prevent non-staff users from
  # executing the necessary binaries)
  file { '/usr/bin/xflock4':
    owner   => root,
    group   => ocfstaff,
    mode    => '0754',
    source  => 'puppet:///modules/ocf_desktop/xsession/xflock4',
    require => Package['xscreensaver'];
  }

  # improve font rendering
  file {
    # disable autohinter
    '/etc/fonts/conf.d/10-autohint.conf':
      ensure => absent;
    # enable subpixel rendering
    '/etc/fonts/conf.d/10-sub-pixel-rgb.conf':
      ensure => symlink,
      links  => manage,
      target => '/usr/share/fontconfig/conf.avail/10-sub-pixel-rgb.conf';
    # enable LCD filter
    '/etc/fonts/conf.d/11-lcdfilter-default.conf':
      ensure => symlink,
      links  => manage,
      target => '/usr/share/fontconfig/conf.avail/11-lcdfilter-default.conf';
    # enable hinting and anti-aliasing
    '/etc/fonts/local.conf':
      source => 'puppet:///modules/ocf_desktop/xsession/fonts.conf';
  }

  # auto logout users
  package {
    [
      'xautolock',
      'gir1.2-notify-0.7',
    ]:;
  }

  file { '/usr/local/bin/auto-lock':
    mode   => '0755',
    source => 'puppet:///modules/ocf_desktop/xsession/auto-lock';
  }

  file { '/usr/local/bin/staff-logout':
    mode   => '0755',
    source => 'puppet:///modules/ocf_desktop/xsession/staff-logout';
  }

  # xscreensaver settings: blank background, disable new login
  file {
    '/etc/X11/Xresources/XScreenSaver':
      content => "*newLoginCommand:\n*mode: blank\n";
    # xfce overrides our newLoginCommand with a stupid wrapper script
    '/etc/xdg/autostart/xscreensaver.desktop':
      source  => 'puppet:///modules/ocf_desktop/xsession/xscreensaver.desktop',
      require => Package['xscreensaver'];
  }

  # Use GTK+ theme for Qt 4 apps
  file { '/etc/xdg/Trolltech.conf':
      source => 'puppet:///modules/ocf_desktop/xsession/Trolltech.conf';
  }

  # IBus
  file {
    '/etc/xdg/autostart/ibus.desktop':
      source  => 'puppet:///modules/ocf_desktop/xsession/ibus.desktop',
      require => Package['ibus'];
  }

  # KDE Logout
  file {
    '/usr/share/applications/logout.desktop':
      source  => 'puppet:///modules/ocf_desktop/xsession/logout.desktop',
  }

  file {
    ['/usr/local/share/plasma', '/usr/local/share/plasma/plasmoids']:
      ensure => directory;
    '/usr/local/share/plasma/plasmoids/com.github.zren.commandoutput':
      ensure  => directory,
      source  => 'puppet:///modules/ocf_desktop/kde-applets/plasma-applet-commandoutput/package',
      recurse => true;
  }
}
