#!/usr/bin/env python
# coding=utf-8
#
#  Created by Jun Fang on 15-12-23.
#  Copyright (c) 2015年 Jun Fang. All rights reserved.

import logging
import os, sys
from multiprocessing import Process, Queue
from kafka.client import KafkaClient
from kafka.producer import SimpleProducer
import psycopg2
import binascii
import json
import memcache
import psycopg2.extras
from Crypto.Cipher import AES
from Crypto.Hash import CMAC
from database import NodeModel, GatewayModel
from message import *
import time

from gw_msg cimport gw_msg_type_e, gw_msg_header_t 
from node_msg cimport lora_mac_header_t, lora_join_req_msg_t, lora_frame_header_t  

default_key = [0x2B, 0x7E, 0x15, 0x16, 0x28, 0xAE, 0xD2, 0xA6, 0xAB, 0xF7, 0x15, 0x88, 0x09, 0xCF, 0x4F, 0x3C]

current_milli_time = lambda: int(round(time.time() * 1000))

cdef class MsgParserProcess(Process):
    def __init__(self, kafka_addr, kafka_port, db_host, db_port, db_user, db_pwd, sock, memcached_list):
        super(MsgParserProcess, self).__init__()
        self.queue = Queue()
        self.sock = sock
        try:
            self.client = KafkaClient(str(kafka_addr) + ':' + str(kafka_port))
            self.kafka_conn = SimpleProducer(self.client)

            self.conn = psycopg2.connect(database='lora', user=db_user, password=db_pwd, host=db_host, port=db_port)
            self.db = self.conn.cursor(cursor_factory = psycopg2.extras.RealDictCursor)

            self.mc = memcache.Client(memcached_list)

            self.node_model = NodeModel(self.db, self.mc)
            self.gateway_model = GatewayModel(self.db, self.mc)
        except Exception, e:
            logging.error(e)
            raise ValueError

        self.process_func = {
            PUSH_DATA: self.gw_push_data_process,
            PUSH_ACK:  self.gw_push_ack_process,
            PULL_DATA: self.gw_pull_data_process,
            PULL_RESP: self.gw_pull_resp_process,
            PULL_ACK:  self.gw_pull_ack_process,
        }

        #for debug
        self.count = 0

    def get_queue(self):
        return self.queue

    cdef uint8_t *generate_mic(self, uint8_t *data, uint32_t data_len, uint32_t address, int8_t up, uint32_t seq):
        mic = []
        b = []
        b.append(0x49) #authentication flags
        b.extend([0, 0, 0, 0])
        if up:
            b.append(0)
        else:
            b.append(1)
        b.extend([address[1], address[0], address[3], address[2]])
        b.extend([seq & 0xFF, seq >> 8 & 0xFF, seq >> 16 & 0xFF, seq >> 24 & 0xFF])
        b.extend([0, data_len])

        auth_key = self.node_model.get_node_auth_key(binascii.hexlify(bytearray(address)))
        if not auth_key:
            secret = default_key
        else:
            secret = auth_key

        #just for test
        secret = ''.join(map(chr, default_key))
        cobj = CMAC.new(secret, ciphermod=AES)
        cobj.update(''.join(map(chr, b)))
        cobj.update(''.join(map(chr, data)))
        mic = cobj.hexdigest()[:8]
        return mic

    def send_ack(self, from_addr, recv_msg, msg_type):
        data = []
        data.append(LORA_VERSION_1)
        data.append(recv_msg.token >> 8 & 0xFF)
        data.append(recv_msg.token & 0xFF)
        data.append(msg_type)
        self.sock.sendto(binascii.hexlify(bytearray(data)), from_addr)

    cdef bool lora_join_req_process(self, struct sockaddr *from_addr, lora_mac_header_t *mac_header, uint8_t *data, uint32_t length):
        cdef lora_join_req_msg_t *join_req 

        if length < cython.sizeof(lora_join_req_msg_t):
            return False

        join_req = (lora_join_req_msg_t *)data 

        node = self.node_model.get_node_by_eui(join_req.dev_eui)
        if node == None:
            return False

        #check app eui
        if node['app_eui'] != join_req.app_eui:
            logging.error('App EUI mismatch')
            return False

        if node['dev_nonce'] == join_req.dev_nonce:
            logging.error('Device nonce is same as before, reject')
            return False
        else:
            self.node_model.set_node_nonce(join_req.dev_eui, join_req.dev_nonce)

        return True

    cdef bool lora_data_process(self, struct sockaddr *from_addr, lora_mac_header_t *mac_header, uint8_t *data, uint32_t length, int8 confirmed):
        cdef lora_frame_header_t *frame_header
        cdef uint8_t opt_len

        if length < cython.sizeof(lora_frame_header_t):
            return False

        frame_header = (lora_frame_header_t *)data

        node = self.node_model.get_node_by_addr(frame_header.dev_addr)
        if node == None:
            return False

        opt_len = ((uplink_fctrl_t *)frame_header.fctrl).fopts_len 

        mic = self.generate_mic(data, length, frame_header.dev_addr, True, node_data.seq)
        if mic != binascii.hexlify(bytearray(node_data.mic)):
            logging.error('MIC mismatch')
            return

        if node_data.seq == node['pkt_seq']:
            #same pkt
            return

        return True

    cdef void gw_push_data_process(self, struct sockaddr *from_addr, gw_msg_header_t *gw_msg_header, uint8_t *data, uint32_t length):
        cdef lora_mac_header_t *lora_mac_header 

        try:
            gw_data = json.loads(data)
        except Exception, e:
            logging.error('Parse gateway data error:' % str(e))
            return

        if 'rxpk' in gw_data:
            #check gw data, like rssi, snr, etc..

            for rxpk in gw_data.rxpk:
                if 'data' in rxpk:
                    if len(rxpk['data']) > cython.sizeof(lora_mac_header_t):
                        lora_mac_header = (lora_mac_header_t *)rxpk['data']
     
                        if lora_mac_header.msg_type == JOIN_REQ:
                            lora_join_req_process(from_addr, lora_mac_header, data + cython.sizeof(lora_mac_header_t),
                                                  len(rxpk['data']) - cython.sizeof(lora_mac_header_t))
                        elif lora_mac_header.msg_type == UNCOMFIRMED_DATA_UP:
                            lora_data_process(from_addr, lora_mac_header, data + cython.sizeof(lora_mac_header_t), 
                                              len(rxpk['data']) - cython.sizeof(lora_mac_header_t), False)
                        elif lora_mac_header.msg_type == COMFIRMED_DATA_UP:
                            lora_data_process(from_addr, lora_mac_header, data + cython.sizeof(lora_mac_header_t), 
                                              len(rxpk['data']) - cython.sizeof(lora_mac_header_t), True)
                        else:
                            logging.error('Unsupoort message type') 
                            
                        return

                dev_addr = binascii.hexlify(bytearray(node_data.address))
                node = self.node_model.get_node_by_addr(dev_addr)
                if not node:
                    logging.error('Node do not exist')
                    return

                #TODO: check mic etc..
                mic = self.generate_mic(node_data.bin_data, node_data.len, node_data.address, True, node_data.seq)
                if mic != binascii.hexlify(bytearray(node_data.mic)):
                    logging.error('MIC mismatch')
                    return

                if node_data.seq == node['pkt_seq']:
                    #same pkt
                    return

                if node_data.frame_type == MSG_TYPE_JOIN_REQ:
                    try:
                        join_req = JoinReqMessage(node_data.bin_data)  
                        #check app eui
                        if node['app_eui'] != join_req.app_eui:
                            logging.error('App EUI mismatch')
                            return
                        
                        #check dev eui
                        if node['dev_eui'] != join_req.dev_eui:
                            logging.error('Device EUI mismatch')
                            return

                        if node['dev_nonce'] == join_req.dev_nonce:
                            logging.error('Device nonce is same as before, reject')
                            return
                        else:
                            self.node_model.set_node_nonce(dev_addr, join_req.dev_nonce)          

                    except Exception, e:
                        logging.error(e)
                        return
  
                try:
                    gw = self.node_model.get_node_best_gw(dev_addr)
                    if gw and gw['rssi'] < rxpk['rssi'] or not gw:
                        self.node_model.set_node_best_gw(dev_addr, binascii.hexlify(bytearray(msg.gw_mac)), from_addr, rxpk['rssi'])
                except Exception, e:
                    logging.error(e)
                    return

                app_eui = self.node_model.get_node_app_eui(dev_addr)
                if app_eui:
                    self.kafka_conn.send_messages(app_eui, {'rxpk':[rxpk]})
                else:
                    logging.error('App EUI does not exist')
                    return

                self.node_mode.set_node_pkt_seq(dev_addr, node_data.seq)

        elif 'stat' in gw_data.__dict__:
            return
        elif 'command' in gw_data.__dict__:
            return
        else:
            return

        #don't forget ack
        self.send_ack(from_addr, msg, PUSH_ACK)

        return

    cdef void gw_push_ack_process(self, struct sockaddr *from_addr, gw_msg_header_t *gw_msg_header, uint8_t *data, uint32_t length):
        return

    cdef void gw_pull_data_process(self, struct sockaddr *from_addr, gw_msg_header_t *gw_msg_header, uint8_t *data, uint32_t length):
        #don't forget ack
        self.send_ack(from_addr, msg, PULL_ACK)
        return

    cdef void gw_pull_resp_process(self, struct sockaddr *from_addr, gw_msg_header_t *gw_msg_header, uint8_t *data, uint32_t length):
        return

    cdef void gw_pull_ack_process(self, struct sockaddr *from_addr, gw_msg_header_t *gw_msg_header, uint8_t *data, uint32_t length):
        return

    cdef void process_data(self, struct sockaddr *from_addr, uint8_t *data, uint32_t length):
        cdef gw_msg_header_t *gw_msg_header = (gw_msg_header_t *)data
        
        if length < cython.sizeof(gw_msg_header_t):
            logging.error('Gateway message length error:%d' % length)
            return     

        if gw_msg_header.version != 1:
            logging.error('Gateway message version error:%d' % gw_msg_header.version)
            return

        if self.process_func[gw_msg_header.msg_type]:
            self.process_func[gw_msg_header.msg_type](from_addr, gw_msg_header, data + cython.sizeof(gw_msg_header_t), 
                                                      length - cython.sizeof(gw_msg_header_t))
        else:
            logging.error('Process data error:%s' % str(e))

        return

    def run(self):
        while True:
            msg = self.queue.get()
            data = msg['data']
            from_addr = msg['addr']
            length = msg['len']

            #process data
            try:
                self.process_data(from_addr, data, length)
            except Exception, e:
                logging.error('Error in process_data: %s' % str(e))
                pass

