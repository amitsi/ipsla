# IPSLA
IPSLA Script will monitor connection links for its availability. If primary link is down, it will create backup static link, until primary link comes up again.

This scripts is compatible with Solaris and Linux platforms.

### Dependencies
ssmtp package (version 2.64)

### How to use
Script takes a YML file as an input. Following shows a sample YML file:
```
LinkTrackIP1:10.10.10.100
-switch_host:aquila-ext-43
-switch_username:network-admin
-switch_password:test123
-vrouter_name:test-vr
-network:10.10.10.0
-netmask:255.255.255.0
-gateway:10.10.10.1
-distance:100
-custom_message:This is the link to US DC
LinkTrackIP2:11.11.11.100
-switch_host:aquila-ext-43
-switch_username:network-admin
-switch_password:test123
-vrouter_name:test-vr
-network:11.11.11.0
-netmask:255.255.255.0
-gateway:11.11.11.1
-distance:100
-custom_message:This is the link to Germany DC
email_id:<EMAIL-ID>
email_password:<EMAIL-PASSWORD>
link_down_message:Link is not reachable
link_up_message:Link is back up
sysadmin:<SYSADMIN-EMAIL-ADDRESS>
ping_timer:3
failure_threshold:2
keep_backup_route:false
```

For every link to track specify the following set of items per link:
```
LinkTrackIP:Remote IP to track
-switch_host:Switch from where to track
-switch_username:Switch username
-switch_password:Switch password
-vrouter_name:vRouter from which to send ping
-network:Network info to add backup route
-netmask:Netmask info to add backup route
-gateway:Gateway info to add backup route
-distance:Distance info to add backup route
-custom_message:Per link custom message to be added in notification email
```

And other general configuration items:
```
email_id:Email-ID from which to send emails
email_Password:Email password
link_down_message:Email message content when a link goes down
link_up_message:Email message content when a link comes up
sysadmin:Email-ID to send notifications to
ping_timer:Number of seconds of delay between each ping
failure_threshold:Maximum number of ping failures to take, after which send notification
keep_backup_route:Once link comes backup, flag to remove backup route or not
```
