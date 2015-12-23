PYVERSION=2.7
PYPREFIX=/usr
INCLUDES=-I$(PYPREFIX)/include/python$(PYVERSION) -I./
LINK=-lpython$(PYVERSION)


all : network_server

network_server: main.o forward.so database.so gw_msg.so lora_msg.so app_msg.so parser.so
	$(CC) -o $@ $^ $(INCLUDES) $(LINK)

main.o: main.c
	$(CC) -c $^ $(INCLUDES) $(LINK) 

forward.so: forward.c
	$(CC) $(INCLUDES) $(LINK) -shared -o forward.so -fPIC forward.c

database.so: database.c
	$(CC) $(INCLUDES) $(LINK) -shared -o database.so -fPIC database.c

app_msg.so: app_msg.c
	$(CC) $(INCLUDES) $(LINK) -shared -o app_msg.so -fPIC app_msg.c

gw_msg.so: gw_msg.c
	$(CC) $(INCLUDES) $(LINK) -shared -o gw_msg.so -fPIC gw_msg.c

lora_msg.so: lora_msg.c
	$(CC) $(INCLUDES) $(LINK) -shared -o lora_msg.so -fPIC lora_msg.c

parser.so: parser.c
	$(CC) $(INCLUDES) $(LINK) -shared -o parser.so -fPIC parser.c

forward.c: forward.pyx
	cython forward.pyx

database.c: database.pyx
	cython database.pyx 

main.c: main.pyx
	cython --embed main.pyx 

app_msg.c: app_msg.pyx
	cython app_msg.pyx 

gw_msg.c: gw_msg.pyx
	cython gw_msg.pyx 

lora_msg.c: lora_msg.pyx
	cython lora_msg.pyx 

parser.c: parser.pyx
	cython parser.pyx 

clean: 
	rm -rf *.c *.o *.so *.pyc network_server 2> /dev/null 
