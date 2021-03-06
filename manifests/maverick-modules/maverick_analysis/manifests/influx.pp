class maverick_analysis::influx (
    $source = "https://github.com/influxdata/influxdb.git",
    $branch = "v1.2.4",
    $influxdb_version = "1.3.3-1",
    $active = true,
) {
    
    # Install Go
    ensure_packages(["golang"])

    # Install influx repo
    if $::operatingsystem == "Debian" {
        $_influx_command = "/bin/bash -c 'source /etc/os-release; test \$VERSION_ID = \"7\" && echo \"deb https://repos.influxdata.com/debian wheezy stable\" | sudo tee /etc/apt/sources.list.d/influxdb.list; test \$VERSION_ID = \"8\" && echo \"deb https://repos.influxdata.com/debian jessie stable\" | sudo tee /etc/apt/sources.list.d/influxdb.list'"
    } elsif $::operatingsystem == "Ubuntu" {
        $_influx_command = "/bin/bash -c 'source /etc/lsb-release; echo \"deb https://repos.influxdata.com/\${DISTRIB_ID,,} \${DISTRIB_CODENAME} stable\" | sudo tee /etc/apt/sources.list.d/influxdb.list'"
    }

    # Install influx repo key
    exec { "influx-key":
        command         => "/usr/bin/curl -sL https://repos.influxdata.com/influxdb.key | sudo apt-key add -",
        unless          => "/usr/bin/apt-key list |/bin/egrep '2582\s?E0C5'",
    } ->
    exec { "influx-repo":
        command         => $_influx_command,
        creates         => "/etc/apt/sources.list.d/influxdb.list",
    } ->
    # Do an apt update if necessary
    exec { "influx-aptupdate":
        command     => "/usr/bin/apt update",
        unless      => "/usr/bin/apt-cache showpkg influxdb |grep influxdata.com"
    } ->
    # Install influxdb
    package { "influxdb":
        ensure      => $influxdb_version,
        require     => [ Exec["influx-repo"], Exec["influx-aptupdate"] ],
    } ->
    file { "/srv/maverick/data/config/analysis/influxdb.conf":
        content     => template("maverick_analysis/influxdb.conf.erb"),
        owner       => "mav",
        group       => "mav",
        notify      => Service_wrapper["maverick-influxd"],
    } ->
    file { ["/srv/maverick/data/analysis/influxdb", "/srv/maverick/data/analysis/influxdb/meta", "/srv/maverick/data/analysis/influxdb/wal", "/srv/maverick/data/analysis/influxdb/data", "/srv/maverick/var/log/analysis"]:
        owner       => "mav",
        group       => "mav",
        ensure      => directory,
        mode        => "755",
    } ->
    file { "/etc/systemd/system/maverick-influxd.service":
        source      => "puppet:///modules/maverick_analysis/influxd.service",
        owner       => "root",
        group       => "root",
        mode        => "644",
        notify      => Exec["maverick-systemctl-daemon-reload"],
    } ->
    exec { "influxd-systemd-activate":
        command     => "/bin/systemctl daemon-reload",
        unless      => "/bin/systemctl list-units |grep maverick-influxd",
    } ->
    # Ensure system influxd instance is stopped
    service_wrapper { "influxdb":
        ensure      => stopped,
        enable      => false,
    }
    
    if $active == true {
        service_wrapper { "maverick-influxd":
            ensure      => running,
            enable      => true,
            require     => [ Service_wrapper["influxdb"], Class["maverick_analysis::collect"] ],
        }
    } else {
        service_wrapper { "maverick-influxd":
            ensure      => stopped,
            enable      => false,
            require     => [ Service_wrapper["influxdb"], Class["maverick_analysis::collect"] ],
        }
    }
    
    # Ensure maverick metrics db exists
    # Note: Disabling the exec below that creates influx database.  Instead, we rely on mavlogd to do this.
    #exec { "influx-maverickdb":
    #    command         => "/bin/sleep 10; /usr/bin/influx -execute 'create database maverick'",
    #    unless          => "/usr/bin/influx -execute 'show databases' |grep maverick",
    #    user            => "mav",
    #    require         => Service_wrapper["maverick-influxd"],
    #}
    
    # Install python library
    install_python_module { "pip-influxdb":
        ensure          => atleast,
        version         => "4.1.1",
        pkgname         => "influxdb",
    }

    # Configure collect to send metrics to influxdb
    collectd::plugin::network::server{'localhost':
        port            => 25826,
        securitylevel   => "None",
        require         => Service_wrapper["maverick-influxd"],
    }

}