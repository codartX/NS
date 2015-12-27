#!/usr/bin/env python
# coding=utf-8
#
#  Created by Jun Fang on 15-12-23.
#  Copyright (c) 2015年 Jun Fang. All rights reserved.

import logging
import json
import binascii
import base64
import array
import socket

MSG_TYPE_JOIN_REQ                   = 0b000
MSG_TYPE_JOIN_ACCEPT                = 0b001
MSG_TYPE_UNCONFIRMED_DATA_UP        = 0b010
MSG_TYPE_UNCONFIRMED_DATA_DOWN      = 0b011
MSG_TYPE_CONFIRMED_DATA_UP          = 0b100
MSG_TYPE_CONFIRMED_DATA_DOWN        = 0b101
MSG_TYPE_RFU                        = 0b110
MSG_TYPE_PROPRIETARY                = 0b111

class NodeMacData():
    def __init__(self, raw_data):
        try:
            data = binascii.b2a_hex(binascii.a2b_base64(raw_data))
            data = map(ord, data.decode('hex'))
            self.__dict__.update({'data': data})

            self.__dict__.update({'len': len(data)})

            frame_type = (data[0] & 0xe0) >> 5
            self.__dict__.update({'frame_type': frame_type})

            rfu = (data[0] & 0x1C) >> 2
            self.__dict__.update({'rfu': rfu})

            major = data[0] & 0x03
            self.__dict__.update({'major': major})

            mac_header = data[:1]
            self.__dict__.update({'mac_header': mac_header})

            mac_payload = data[1:]
            self.__dict__.update({'mac_payload': mac_payload})

        except Exception, e:
            logging.error('Node mac data parse fail:' % str(e))
            raise ValueError

class NodeFrameData():
    def __init__(self, data):
        try:
            header = data[:7]

            #address = header[0:4]
            #ntohl
            address = [header[1], header[0], header[3], header[2]]
            self.__dict__.update({'address': address})

            fctrl = header[4]
            self.__dict__.update({'fctrl': fctrl})

            fcnt = (header[6] << 8) + header[5]
            self.__dict__.update({'fcnt': fcnt})

            adr = fctrl & 0x80
            self.__dict__.update({'adr': adr})

            adr_ack_req = fctrl & 0x40
            self.__dict__.update({'adr_ack_req': adr_ack_req})

            ack = fctrl & 0x20
            self.__dict__.update({'ack': ack})

            opts_len = fctrl & 0x0F
            self.__dict__.update({'opts_len': opts_len})

            if opts_len > 0:
                option = data[7: 7 + opts_len - 1]
                self.__dict__.update({'option': option})
            else:
                self.__dict__.update({'option': []})

            port = data[7 + opts_len]
            self.__dict__.update({'port': port})

            payload = data[7 + opts_len: -4]
            self.__dict__.update({'payload': payload})

            mic = data[-4:]
            self.__dict__.update({'mic': mic})

        except Exception, e:
            logging.error('FrameData error:%s' % str(e))
            raise ValueError

class NodeJoinReq():
    def __init__(self, data):
        try:
            if len(data) != 22:
                logging.error('JoinReq length error')
                raise ValueError
            
            app_eui = data[0: 8]
            self.__dict__.update({'app_eui': app_eui})
            dev_eui = data[8: 16]
            self.__dict__.update({'dev_eui': dev_eui})
            dev_nonce = data[16: 18]
            self.__dict__.update({'dev_nonce': dev_nonce})
            mic = data[18: 22]
            self.__dict__.update({'mic': mic})
        except Exception, e:
            logging.error('JoinReq error:%s' % str(e))
            raise ValueError

class NodeJoinAccept():
    def __init__(self, data):
        try:
            if len(data) != 12 or len(data) != 28:
                logging.error('JoinResp length error')
                raise ValueError
            
            app_nonce = data[0: 3]
            self.__dict__.update({'app_nonce': app_nonce})
            net_id = data[3: 6]
            self.__dict__.update({'net_id': net_id})
            dev_addr = data[6: 10]
            self.__dict__.update({'dev_addr': dev_addr})
            dl_settings = data[10]
            self.__dict__.update({'dl_settings': dl_settings})
            rx_delay = data[11]
            self.__dict__.update({'rx_delay': rx_delay})
            if len(data) == 28:
                self.__dict__.update({'cf_list': data[12:28]})
            else:
                self.__dict__.update({'cf_list': []})
             
        except Exception, e:
            logging.error('JoinResp error:%s' % str(e))
            raise ValueError

