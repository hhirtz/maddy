maddy-smtp(5) "maddy mail server" "maddy reference documentation"

; TITLE SMTP endpoint module

Module 'smtp' is a listener that implements ESMTP protocol with optional
authentication and Submission support. Incoming messages are processed in
accordance with pipeline rules (explained in Message pipeline section below).

```
smtp smtp://0.0.0.0:25 smtps://0.0.0.0:587 {
    hostname example.org
    tls /etc/ssl/private/cert.pem /etc/ssl/private/pkey.key
    io_debug no
    debug no
    insecure_auth no
    read_timeout 10m
    write_timeout 1m
    max_message_size 32M
    auth pam
    submission no
    defer_sender_reject yes

    # Example pipeline ocnfiguration.
    destination example.org {
        deliver_to local_mboxes
    }
    default_destination {
        reject
    }
}
```

## Configuration directives

*Syntax*: hostname _string_ ++
*Default*: global directive value

Server name to use in SMTP banner.

```
220 example.org ESMTP Service Ready
```

*Syntax*: tls _certificate_path_ _key_path_ { ... } ++
*Default*: global directive value

TLS certificate & key to use. Fine-tuning of other TLS properties is possible
by specifing a configuration block and options inside it:
```
tls cert.crt key.key {
    protocols tls1.2 tls1.3
}
```
See section 'TLS configuration' in *maddy*(1) for valid options.

*Syntax*: io_debug _boolean_ ++
*Default*: no

Write all commands and responses to stderr.

*Syntax*: debug _boolean_ ++
*Default*: global directive value

Enable verbose logging.

*Syntax*: insecure_auth _boolean_ ++
*Default*: no (yes if TLS is disabled)

Allow plain-text authentication over unencrypted connections. Not recommended!

*Syntax*: read_timeout _duration_ ++
*Default*: 10m

I/O read timeout.

*Syntax*: write_timeout _duration_ ++
*Default*: 1m

I/O write timeout.

*Syntax*: max_message_size _size_ ++
*Default*: 32M

Limit the size of incoming messages to 'size'.

*Syntax*: auth _block_name_ ++
*Default*: not specified

Use an authentication module with a specified configuration block name.

*Syntax*: submission _boolean_ ++
*Default*: no

Preprocess messages before pushing them to target and require authentication
for all operations. You should use it for Submission protocol endpoints.

*Syntax*: defer_sender_reject _boolean_ ++
*Default*: yes

Apply sender-based checks and routing logic when first RCPT TO command
is received. This allows maddy to log recipient address of the rejected
message and also improves interoperability with (improperly implemented)
clients that don't expect an error early in session.

# Submission module

Alias to smtp module with submission directive used by default.

# Mesage pipeline

Message pipeline is a set of module configuration blocks and associated
rules that describe how to handle messages.

The pipeline is responsible for
- Running message filters (called "checks"), (e.g. DKIM signature verification,
  DNSBL lookup and so on).
- Running message modifiers (e.g. DKIM signature creation).
- Assocating each message recipient with one or more delivery targets.
  Delivery target is a module (with corresponding config block) that
  does final processing (delivery) of the message.

Message handling flow is as follows:
. Execute checks referenced in top-level 'check' block (if any)
. Execute modifiers referenced in top-level 'modify' block (if any)
. If there are 'source' blocks - select one that matches message sender (as
  specified in MAIL FROM). If there are no 'source' blocks - entire
  configuration is assumed to be the 'default_source' block.
. Execute checks referenced in 'check' block inside selected 'source' block
  (if any).
. Execute modifiers referenced in 'modify' block inside selected 'source'
  block (if any).

Then, for each recipient:
. Select 'destination' block that matches it. If there are
  no 'destination' blocks - entire used 'source' block is interpreted as if it
  was a 'default_destination' block.
. If used block contains 'reject' directive - reject the recipient with
  specified SMTP status code.
. If used block contains 'deliver_to' directive - pass the message to the
  specified target module configuration block. Only recipients that are handled
  by used block are visible to the target.

Each recipient is handled only by a single 'destination' block, duplicated
match rules are not allowed.
```
destination example.org {
    deliver_to targetA
}
destination example.org { # ambiguous and thus not allowed
    deliver_to targetB
}
```
Same goes for 'source' blocks, each message is handled only by a single block.

Each recipient block should contain at least one 'deliver_to' directive or
'reject' directive. If 'destination' blocks are used, then
'default_destination' block should also be used to specify behavior for
unmatched recipients.  Same goes for source blocks, 'default_source' should be
used if 'source' is used.

That is, pipeline configuration should explicitly specify behavior for each
possible sender/recipient combination.

Additionally, directives that specify final handling decision ('deliver_to',
'reject') can't be used at the same level as source/destination rules.
Consider example:
```
destination example.org {
    deliver_to local_mboxes
}
reject
```
It is not obvious whether 'reject' applies to all recipients or
just for non-example.org ones, hence this is not allowed.

Complete configuration example using all of the mentioned directives:
```
check {
    # Run a check to make sure source SMTP server identification
    # is legit.
    require_matching_ehlo
}

# Messages coming from senders at example.org will be handled in
# accordance with the following configuration block.
source example.org {
    # We are example.com, so deliver all messages with recipients
    # at example.com to our local mailboxes.
    destination example.com {
        deliver_to local_mailboxes
    }

    # We don't do anything with recipients at different domains
    # because we are not an open relay, thus we reject them.
    default_destination {
        reject 521 5.0.0 "User not local"
    }
}

# We do our business only with example.org, so reject all
# other senders.
default_source {
    reject
}
```

## Directives

*Syntax*: check { ... } ++
*Context*: pipeline configuration, source block, destination block

List of the configuration block names for checks that should be executed on
messages handled by block where 'check' is placed in.

Note that message body checks placed in destination block are currently
ignored. Due to the way SMTP protocol is defined, they would cause message to
be rejected for all recipients which is not what you usually want when using
such configurations.

Example:
```
check {
    # Reference implicitly defined default configuration for check.
    require_matching_ehlo

    # Inline definition of custom config.
    require_source_mx {
         # Configuration for require_source_mx goes here.
         fail_action reject
    }
}
```

*Syntax*: modify { ... } ++
*Default*: not specified ++
*Context*: pipeline configuration, source block, destination block

List of the configuration block names for modifiers that should be executed on
messages handled by block where 'modify' is placed in.

Message modifiers are similar to checks with the difference in that checks
purpose is to verify whether the message is legitimate and valid per local
policy, while modifier purpose is to post-process message and its metadata
before final delivery.

For example, modifier can replace recipient address to make message delivered
to the different mailbox or it can cryptographically sign outgoing message
(e.g. using DKIM). Some modifier can perform multiple unrelated modifications
on the message.

NOTE: Modifiers that affect the message header or source address can
be used only globally or on per-source basis, they will be no-op
inside destination blocks.

*Syntax*: ++
    reject _smtp_code_ _smtp_enhanced_code_ _error_description_ ++
    reject _smtp_code_ _smtp_enhanced_code_ ++
    reject _smtp_code_ ++
    reject ++
*Context*: destination block

Messages handled by the configuration block with this directive will be
rejected with the specified SMTP error.

If you aren't sure which codes to use, use 541 and 5.4.0 with your message or
just leave all arguments out, the error description will say "message is
rejected due to policy reasons" which is usually what you want to mean.

'reject' can't be used in the same block with 'deliver_to' or
'destination/source' directives.

Example:
```
reject 541 5.4.0 "We don't like example.org, go away"
```

*Syntax*: deliver_to _target-config-block_ ++
*Context*: pipeline configuration, source block, destination block

Deliver the message to the referenced delivery target. What happens next is
defined solely by used target. If deliver_to is used inside 'destination'
block, only matching recipients will be passed to the target.

*Syntax*: source _rules..._ { ... } ++
*Context*: pipeline configuration

Handle messages with MAIL FROM value (sender address) matching any of the rules
in accordance with the specified configuration block.

"Rule" is either a domain or a complete address. Duplicate rules are not
allowed. Matching is case-insensitive.

Example:
```
# All messages coming from example.org domain will be delivered
# to local_mailboxes.
source example.org {
    deliver_to local_mailboxes
}
# Messages coming from different domains will be rejected.
default_source {
    reject 521 5.0.0 "You were not invited"
}
```

*Syntax*: destination _rule..._ { ... } ++
*Context*: pipeline configuration, source block

Handle messages with RCPT TO value (recipient address) matching any of the
rules in accordance with the specified configuration block.

"Rule" is either a domain or a complete address. Duplicate rules are not
allowed. Matching is case-insensitive.

Note that messages with multiple recipients are split into multiple messages if
they have recipients matched by multiple blocks. Each block will see the
message only with recipients matched by its rules.

Example:
```
# Messages with recipients at example.com domain will be
# delivered to local_mailboxes target.
destination example.com {
    deliver_to local_mailboxes
}

# Messages with other recipients will be rejected.
default_destination {
    rejected 541 5.0.0 "User not local"
}
```
