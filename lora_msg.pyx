#!/usr/bin/env python
# coding=utf-8

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
            self.__dict__.update({'data': data[:-4]})# exclude mic

            self.__dict__.update({'len': len(data) - 4})#exclude mic

            frame_type = header[0] & 0xe0 >> 5
            self.__dict__.update({'frame_type': frame_type})

            rfu = header[0] & 0x1C >> 2
            self.__dict__.update({'rfu': rfu})

            major = header[0] & 0x03
            self.__dict__.update({'major': major})

            mac_payload = data[1: -4]
            self.__dict__.update({'mac_payload': mac_payload})

            mic = data[-4:]
            self.__dict__.update({'mic': mic})

        except Exception, e:
            logging.error(e)
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

            fcnt = header[6] << 8 + header[5]
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
                option = data[7: 7 + option_len - 1]
                self.__dict__.update({'option': option})
            else:
                self.__dict__.update({'option': []})

            port = data[7 + option_len]
            self.__dict__.update({'port': port})

            payload = data[7 + option_len:]
            self.__dict__.update({'payload': payload})

        except Exception, e:
            logging.error('FrameData error:%s' % str(e))
            raise ValueError

class NodeJoinReq():
    def __init__(self, data):
        try:
            app_eui = data[0: 8]
            self.__dict__.update({'app_eui': app_eui})
            dev_eui = data[8: 16]
            self.__dict__.update({'dev_eui': dev_eui})
            dev_nonce = data[16: 18]
            self.__dict__.update({'dev_nonce': dev_nonce})
        except Exception, e:
            logging.error('JoinReq error:%s' % str(e))
            raise ValueError

