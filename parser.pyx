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
from gw_msg import *
from lora_msg import *
from utils import *
import time
import socket

default_key = [0x2B, 0x7E, 0x15, 0x16, 0x28, 0xAE, 0xD2, 0xA6, 0xAB, 0xF7, 0x15, 0x88, 0x09, 0xCF, 0x4F, 0x3C]

current_milli_time = lambda: int(round(time.time() * 1000))

class MsgParserProcess(Process):
    def __init__(self, kafka_addr, kafka_port, db_host, db_port, db_user, db_pwd, sock, memcached_list):
        super(MsgParserProcess, self).__init__()
        self.queue = Queue()
        self.sock = sock
        try:
            #self.client = KafkaClient(str(kafka_addr) + ':' + str(kafka_port))
            #self.kafka_conn = SimpleProducer(self.client)

            self.conn = psycopg2.connect(database='lora', user=db_user, password=db_pwd, host=db_host, port=db_port)
            self.db = self.conn.cursor(cursor_factory = psycopg2.extras.RealDictCursor)

            self.mc = memcache.Client(memcached_list)

            self.node_model = NodeModel(self.db, self.mc)
            self.gateway_model = GatewayModel(self.db, self.mc)
        except Exception, e:
            logging.error('Parser process init fail:%s' % str(e))
            raise ValueError

        self.process_func = {
            GW_PUSH_DATA: self.gw_push_data_process,
            GW_PUSH_ACK:  self.gw_push_ack_process,
            GW_PULL_DATA: self.gw_pull_data_process,
            GW_PULL_RESP: self.gw_pull_resp_process,
            GW_PULL_ACK:  self.gw_pull_ack_process,
        }

        #for debug
        self.count = 0

    def get_queue(self):
        return self.queue

    def generate_frame_mic(self, data, data_len, address, up, seq):
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

    def gw_send_ack(self, from_addr, recv_msg, msg_type):
        data = []
        data.append(LORA_VERSION_1)
        data.append(recv_msg.token >> 8 & 0xFF)
        data.append(recv_msg.token & 0xFF)
        data.append(msg_type)
        self.sock.sendto(binascii.hexlify(bytearray(data)), from_addr)

    def lora_join_req_process(self, mac_header, data, gw):
        try:
            join_req = NodeJoinReq(data)
            dev_eui = binascii.hexlify(bytearray(join_req.dev_eui))
            app_eui = binascii.hexlify(bytearray(join_req.app_eui))
            dev_nonce = binascii.hexlify(bytearray(join_req.dev_nonce))
            node = self.node_model.get_node_by_eui(dev_eui)
            if node == None:
                return
            #check app eui
            if node['app_server_id'] != app_eui:
                logging.error('App EUI mismatch')
                return

            if node['dev_nonce'] == dev_nonce:
                logging.error('Device nonce is same as before, reject')
                return
            else:
                self.node_model.set_node_nonce(dev_eui, dev_nonce)
   
            if 'gw' in node and node['gw']['rssi'] < gw['rssi'] or not 'gw' in node:
                self.node_model.set_node_best_gw_by_eui(dev_eui, binascii.hexlify(bytearray(gw['mac'])), 
                                                        gw['address'], gw['rssi'])

            return

        except Exception, e:
            logging.error('Lora join process fail:%s' % str(e))
            return

    def lora_frame_process(self, mac_header, data, need_confirm, gw):
        try:
            frame_data = NodeFrameData(data)
            dev_addr = binascii.hexlify(bytearray(frame_data.address))
            node = self.node_model.get_node_by_addr(dev_addr)
            if not node:
                logging.error('Node do not exist')
                return

            mac_data = mac_header + data[:-4]
            mic = self.generate_frame_mic(mac_data, len(data) - 4 + 1, frame_data.address, True, frame_data.fcnt)
            if mic != binascii.hexlify(bytearray(frame_data.mic)):
                logging.error('MIC mismatch')
                return

            if 'gw' in node and node['gw']['rssi'] < gw['rssi'] or not 'gw' in node:
                self.node_model.set_node_best_gw(dev_addr, binascii.hexlify(bytearray(gw['mac'])), 
                                                 gw['address'], gw['rssi'])

            if 'seq' in node and frame_data.fcnt == node['seq']:
                logging.error('Seq number is same as before')
                return

            self.node_model.set_node_pkt_seq(dev_addr, frame_data.fcnt)

            app_eui = self.node_model.get_node_app_eui(dev_addr)
            if app_eui:
                print 'app eui:', app_eui
                #self.kafka_conn.send_messages(app_eui, {'rxpk':[rxpk]})
            else:
                logging.error('App EUI does not exist')
                return

            return True
        except Exception, e:
            PrintException()
            logging.error('Lora frame process fail:%s' % str(e))
            return

    def gw_push_data_process(self, from_addr, msg):
        try:
            gw_data = GatewayData(msg.payload)
        except Exception, e:
            logging.error('Parse gateway data error:' % str(e))
            return

        if 'rxpk' in gw_data.__dict__:
            #check gw data, like rssi, snr, etc..

            for rxpk in gw_data.rxpk:
                try:
                    mac_data = NodeMacData(rxpk['data'])
                except Exception, e:
                    logging.error(e)
                    return

                gw = {'mac': msg.gw_mac, 'address': from_addr, 'rssi': rxpk['rssi']}

                if mac_data.frame_type == MSG_TYPE_JOIN_REQ:
                    self.lora_join_req_process(mac_data.mac_header, mac_data.mac_payload, gw)  
                elif mac_data.frame_type == MSG_TYPE_UNCONFIRMED_DATA_UP:
                    self.lora_frame_process(mac_data.mac_header, mac_data.mac_payload, False, gw) 
                elif mac_data.frame_type == MSG_TYPE_CONFIRMED_DATA_UP:
                    self.lora_frame_process(mac_data.mac_header, mac_data.mac_payload, True, gw) 

        elif 'stat' in gw_data.__dict__:
            return
        elif 'command' in gw_data.__dict__:
            return
        else:
            return

        #don't forget ack
        self.gw_send_ack(from_addr, msg, GW_PUSH_ACK)

        return

    def gw_push_ack_process(self, from_addr, msg):
        return

    def gw_pull_data_process(self, from_addr, msg):
        #don't forget ack
        self.gw_send_ack(from_addr, msg, PULL_ACK)
        return

    def gw_pull_resp_process(self, from_addr, msg):
        return

    def gw_pull_ack_process(self, from_addr, msg):
        return

    def process_data(self, from_addr, data, length):
        try:
            msg = GatewayMessage(data, length)
        except Exception, e:
            logging.error('Gateway message parse fail:%s' % str(e))
            return

        if msg.payload:
            try:
                self.process_func[msg.type](from_addr, msg)
            except Exception, e:
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

