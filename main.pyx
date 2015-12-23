#!/usr/bin/env python
# coding=utf-8
import logging
import sys,os, signal, getopt
import socket
import json
from parser import MsgParserProcess
from forward import ForwardProcess

def main():
    try:
        f = open('config.json', 'r')
        raw_data = f.read()
        config_json = json.loads(raw_data)
    except Exception, e:
        print 'Wrong format config file, ', e
        sys.exit()

    if not 'kafka_cfg' in config_json or not 'database_cfg' in config_json or not 'mc_list' in config_json or not 'process_num' in config_json or not 'local_port' in config_json:
        print 'Config file invalid'
        sys.exit()

    try:
        # Set up a UDP server
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 32*1024*1024)

        # Listen on localport 
        # (to all IP addresses on this system)
        listen_addr = ("",config_json['local_port'])
        sock.bind(listen_addr)
    except Exception, e:
        print e
        sys.exit()

    msg_queues = []
    process_pool = []

    try:
        for i in range(int(config_json['process_num'])):
            p = MsgParserProcess(config_json['kafka_cfg']['host'], config_json['kafka_cfg']['port'], config_json['database_cfg']['host'],
                                 config_json['database_cfg']['port'], config_json['database_cfg']['username'], config_json['database_cfg']['password'],
                                 sock, config_json['mc_list'])
            p.daemon = True
            msg_queues.append(p.get_queue())
            process_pool.append(p)
            p.start()

        p = ForwardProcess(config_json['kafka_cfg']['host'], config_json['kafka_cfg']['port'], config_json['database_cfg']['host'],
                           config_json['database_cfg']['port'], config_json['database_cfg']['username'], config_json['database_cfg']['password'],
                           config_json['kafka_cfg']['ns_id'], config_json['mc_list'])
        p.daemon = True
        p.start()
    except Exception, e:
        print 'Process create fail,', e
        sys.exit()

    # Report on all data packets received and
    # where they came from in each case (as this is
    # UDP, each may be from a different source and it's
    # up to the server to sort this out!)
    queue_index = 0
    while True:
        data = bytearray(400)
        length, addr = sock.recvfrom_into(data, 400)
        try:
            msg_queues[queue_index].put({'addr':addr, 'data':data, 'len': length})
        except Exception, e:
            logging.error('Enqueue fail,error:' % str(e))

        queue_index = (queue_index + 1) % len(msg_queues)

if __name__ == "__main__":
    #logging.basicConfig(
    #    format='%(asctime)s.%(msecs)s:%(name)s:%(thread)d:%(levelname)s:%(process)d:%(message)s',
    #    level=logging.DEBUG
    #    )
    main()

