bitreceive
==========

A utility to push notification when bitcoin is received to addresses in wallet


What is it?
===========

A program to be called by bitcore's -walletnotify / -blocknotify to detect receiving transactions


Usage
====

put

```
blocknotify=/path/bitreceive.native blocknotify /path/config_example %s
walletnotify=/path/bitreceive.native walletnotify /path/config_example %s
```

on your coind configuration


What do it solve?
===================

-walletnotify and -blocknotify are a general purpose API to notify when Bitcore sees new blocks or transactions affecting wallet.

This utility filters out transactions that have nothing to do with receiving, and it only notifies minimal necessary information.


How it works?
=================================
Here is an example of config:

```
( 
  (rpcip "127.0.0.1")
  (rpcport 9904)
  (rpcuser "peer")
  (rpcpassword "unity")
  (nconfirm 2)
  (mutex_file "/tmp/bitreceive.lock")
  (state_file "/tmp/bitreceive.state")
  (min_seconds_between_call 5)
  (output_pipe "/tmp/bitreceive.pipe")
)
```

The basic idea is bitreceive uses "listsinceblock" to find ,unconfirmed/or small number of confirmed, transactions on -walletnotify, -blocknotify events.
It keeps track of the latest block number that a transaction reaches the configurable "nconfirm".

nconfirm is the maximum number of confirmation that a transaction update will be relayed to the named pipe. This number should be
the number that you application relies as the minimum number of confirmations a receiving transaction is credited to a user account.
Once it's credited, there's no need to receive the notification on such transaction.

min_seconds_between_call is to prevent too many unnecessary notifications. Because -walletnotify/-blocknotify can go crazy, for example,
once a transaction has one confirm the -walletnotify is called, then -blocknotify will be called right after it,
because it's a new block. Imagine you have 5 unconfirmed txs about to get confirmed, there will be 6 calls where one is only enough,
because we use "listsinceblock" to get all the transactions. The drawback is if there are unconfirm txs hit the wallet within N seconds
after the new block, it won't be notified until the next -walletnotify/-blocknotify. So keep this value low.

here is an example of what you get from the name pipe on one readline:

```
{"last_included_block":"0f5d6c3b994760d90dec345fffe55aa3bf1cff03e4bb74db40b710e26e53b703","incoming":[{"address":"n4J8FqLtP9sqg6Xy5Tpar8hk1WWjkxbuth","amount":9900000,"confirmations":0},{"address":"n4J8FqLtP9sqg6Xy5Tpar8hk1WWjkxbuth","amount":9990000,"confirmations":1},{"address":"n4J8FqLtP9sqg6Xy5Tpar8hk1WWjkxbuth","amount":8000000,"confirmations":2},{"address":"n4J8FqLtP9sqg6Xy5Tpar8hk1WWjkxbuth","amount":9000000,"confirmations":2}]}
```

Since I set nconfirm = 2. So it will be the last time, the last 2 txs show up. So I should make a credit to a user in my database. For other txs, I can just update them on user display.

last_included_block is the block that last transaction reaching the nconfirm occurs. It is given for the case that something bad happens, you can set the variable in the "state_file",
so that bitreceive can start notifying from that block.

So, once I have credited users, I save the "last_included_block" on my db.


What if there's a fork ?
========================

Well, that's why we have the "nconfirm". You should only display the incoming coins, until the number of confirmations reach "nconfirm" and credit them. If a fork affects more than nconfirm,
you are pretty much fucked as design.


Sample code of the named pipe reader ?
======================================

```
#!/bin/bash

while true
do
    if read line < "/tmp/bitreceive.pipe"; then
        echo $line
        # call db or curl to your web
    fi
done
```
