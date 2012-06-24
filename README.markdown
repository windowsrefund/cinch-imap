cinch-imap
==========

The Cinch Imap Plugin. Poll an IMAP mailbox at a defined interval.

Installation
------------

```bash
$ gem install cinch-imap
```

Required Configuration
----------------------

#####:host
The IMAP server
##### :user
The user id
##### :password
The password

Optional Configuration
----------------------

##### :port
The IMAP port. Default is 143.
##### :ssl
Use SSL? Default is false.
##### :interval
Number of seconds between polling. Default is 300.
##### :mark_as_read
Sets the IMAP :Seen flag on polled messages. Default is true.
##### :autostart
The bot will start polling when it joins the channel

Commands
--------

Enable/disable IMAP polling

  !monitor on/off/start/stop

Display status information to the channel

  !monitor show status

Reset the number of messages seen to 0

  !monitor clear

Set polling interval in seconds. Default is 300.

  !monitor interval [n]

Display plugin configuration. The password attribute is skipped.

  !monitor show config

Poll the IMAP mailbox

	!monitor test

Example Configuration
---------------------

<pre ruby>
require 'cinch'
require 'cinch/plugins/imap'

bot = Cinch::Bot.new do
  configure do |c|
    c.server           = "my.ircserver.tld"
    c.nick             = "cinch"
    c.channels         = ["#mychannel"]
    c.plugins.plugins  = [Imap]
 		c.plugins.options[Imap] = {
    	:autostart => true,
   		:host => 'my.imapserver.tld',
      :user => 'me@fqdn.tld',
      :password => "l3tm3out",
      :port => 993,
      :ssl => true,
      :subject_matches => {'ERROR' => '!!', 'SUCCESS' => '..'},
      :from_rewrites => {
        'this@suchalong.silly.address' => 'foo',
        'another@address.that.bugs.me' => 'bugger',
      },	
    }
  end
end

bot.start
</pre>

Now, run your bot.

```bash
  ruby mybot.rb
```

WARNING
-------

When enabled, this plugin will output message sender and subject data to the
channel. Do not enable this plugin on bots that are connected to public
channels if your email data is something you consider to meant for your
eyes only.

TODO
----

The reporting is hardcoded (see the count_database stuff). One day, I'll
break this out into something configurable.
