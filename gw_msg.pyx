#!/usr/bin/env python
# coding=utf-8

import logging
import json

LORA_VERSION_1 = 1

GW_PUSH_DATA = 0
GW_PUSH_ACK  = 1
GW_PULL_DATA = 2
GW_PULL_RESP = 3
GW_PULL_ACK  = 4

GW_MSG_HEADER_LEN = 4
GW_MAC_FULL_ADDR_LEN = 8

class GatewayMessage():
    def __init__(self, data, length):
        try:
            if length < GW_MSG_HEADER_LEN:
                raise ValueError

            version = data[0]
            if version != 1:
                raise ValueError
            else:
                self.__dict__.update({'version': version})

            token = data[1] << 8 | data[2]
            self.__dict__.update({'token': token})

            msg_type = data[3]
            self.__dict__.update({'type': msg_type})

            if length > GW_MSG_HEADER_LEN + GW_MAC_FULL_ADDR_LEN:
                self.__dict__.update({'gw_mac': data[GW_MSG_HEADER_LEN: GW_MSG_HEADER_LEN + GW_MAC_FULL_ADDR_LEN]})
                self.__dict__.update({'payload': data[GW_MSG_HEADER_LEN + GW_MAC_FULL_ADDR_LEN: length]})
            else:
                self.__dict__.update({'gw_mac': None})
                self.__dict__.update({'payload': None})

        except Exception, e:
            logging.error(e)
            raise ValueError

class GatewayData():
    def __init__(self, data):
        try:
            payload = data.decode("utf-8")
            payload_json = json.loads(payload)
            self.__dict__.update(payload_json)
        except Exception, e:
            logging.error('GatewayData error:' % str(e))
            raise ValueError

