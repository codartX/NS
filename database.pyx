#!/usr/bin/env python
# coding=utf-8
#
#  Created by Jun Fang on 15-12-23.
#  Copyright (c) 2015年 Jun Fang. All rights reserved.
import psycopg2.extras
import json

class GatewayModel():
    def __init__(self, db, mc):
        self.db = db
        self.mc = mc

class NodeModel():
    def __init__(self, db, mc):
        self.db = db
        self.mc = mc

    def get_node_by_addr(self, node_addr):
        node = self.mc.get(node_addr)
        if node:
           return json.loads(node)
        else:
           sql = """SELECT * FROM at_lora_nodes WHERE dev_addr = '%s';""" % node_addr
           self.db.execute(sql)
           node = self.db.fetchone()
           if node is not None:
               self.mc.set(node_addr, json.dumps(node))
               return json.loads(node)
           else:
               return None

    def get_node_by_eui(self, node_eui):
        node = self.mc.get(node_eui)
        if node:
           return json.loads(node)
        else:
           sql = """SELECT * FROM at_lora_nodes WHERE dev_eui = '%s';""" % node_eui
           self.db.execute(sql)
           node = self.db.fetchone()
           if node is not None:
               self.mc.set(node_eui, json.dumps(node))
               return json.loads(node)
           else:
               return None

    def get_node_app_eui(self, node_addr):
        node = self.get_node_by_addr(node_addr)
        if 'app_server_id' in node:
            return node['app_server_id']
        else:
            return None

    def get_node_best_gw(self, node_addr):
        node = self.get_node_by_addr(node_addr)
        if 'gw' in node:
            return node['gw']
        else:
            return None

    def get_node_best_gw_by_eui(self, node_eui):
        node = self.get_node_by_eui(node_eui)
        if 'gw' in node:
            return node['gw']
        else:
            return None

    def set_node_best_gw(self, node_addr, gw_mac, gw_addr, rssi):
        node = self.get_node_by_addr(node_addr)
        node['gw'] = {'mac': gw_mac, 'address': gw_addr, 'rssi': rssi}
        self.mc.set(node_addr, json.dumps(node))

    def set_node_best_gw_by_eui(self, node_eui, gw_mac, gw_addr, rssi):
        node = self.get_node_by_addr(node_eui)
        node['gw'] = {'mac': gw_mac, 'address': gw_addr, 'rssi': rssi}
        self.mc.set(node_eui, json.dumps(node))

    def get_node_auth_key(self, node_addr):
        node = self.get_node_by_addr(node_addr)
        if 'authen_key' in node:
            return node['authen_key']
        else:
            return None

    def set_node_nonce(self, node_eui, nonce):
        node = self.get_node_by_eui(node_eui)
        node['dev_nonce'] = nonce
        sql = """UPDATE at_lora_nodes SET dev_nonce = '%s' WHERE dev_eui = '%s';""" % (nonce, node_eui)
        self.db.execute(sql)
        self.mc.set(node_eui, json.dumps(node))

    def set_node_pkt_seq(self, node_addr, seq):
        node = self.get_node_by_addr(node_addr)
        node['pkt_seq'] = seq
        self.mc.set(node_addr, json.dumps(node)) 

    def set_node_nws_key_and_dev_addr(self, node_eui, nws_key, dev_addr):
        node = self.get_node_by_eui(node_eui)
        node['nws_key'] = nws_key
        node['dev_addr'] = dev_addr
        sql = """UPDATE at_lora_nodes SET network_session_ley = '%s', dev_addr = '%s' WHERE dev_eui = '%s';""" % (nws_key, dev_addr, node_eui)
        self.db.execute(sql)
        self.mc.set(node_eui, json.dumps(node)) 
