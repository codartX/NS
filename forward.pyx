#!/usr/bin/env python
# coding=utf-8
#
#  Created by Jun Fang on 15-12-23.
#  Copyright (c) 2015年 Jun Fang. All rights reserved.

import logging
from multiprocessing import Process
from kafka.client import KafkaClient
from kafka.consumer import SimpleConsumer
from database import NodeModel, GatewayModel
import psycopg2
import memcache
import json
from app_msg import *
from lora_msg import *

class ForwardProcess(Process):
    def __init__(self, kafka_addr, kafka_port, db_host, db_port, db_user, db_pwd, ns_id, memcached_list):
        super(ForwardProcess, self).__init__()
        try:
            self.client = KafkaClient(str(kafka_addr) + ':' + str(kafka_port))
            self.kafka_conn = SimpleConsumer(self.client, "cisco", ns_id)

            self.conn = psycopg2.connect(database='lora', user=db_user, password=db_pwd, host=db_host, port=db_port)
            self.db = self.conn.cursor(cursor_factory = psycopg2.extras.RealDictCursor)

            self.mc = memcache.Client(memcached_list)

            self.node_model = NodeModel(self.db, self.mc)
            self.gateway_model = GatewayModel(self.db, self.mc)
        except Exception, e:
            logging.error(e)
            raise ValueError

    def run(self):
        while True:
            try:
                for message in self.kafka_conn:
                    try:
                        msg = AppMessage(message) 
                        mac_data = NodeMacData(msg.data)
                        if mac_data.frame_type == MSG_TYPE_JOIN_ACCEPT:
                            join_accept = NodeJoinAccept(mac_data.mac_payload)
                            #update device info
                            self.node_model.set_node_nws_key_and_dev_addr(msg['dev_eui'], msg['nws_key'], 
                                                                          join_accept.dev_addr)
                            gw = self.node_model.get_node_best_gw_by_eui(msg['dev_eui'])
                            del msg['nws_key']
                            del msg['dev_dui']
                        else:
                            frame_data = NodeFrameData(mac_data.mac_payload) 
                            dev_addr = frame_data.address
                            gw = self.node_model.get_node_best_gw(dev_addr)

                        #send to best gw
                        if gw:
                            self.sock.sendto(message, gw['address']) 
                        else:
                            logging.error('Get best gw fail')
                            return

                    except Exception, e:
                        logging.error('App message parse fail:%s' % str(e))
                        return
                        
            except Exception, e:
                logging.error('Error in forward msg to gateway: %s' % str(e))
                pass
