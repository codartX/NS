PYVERSION=2.7
PYPREFIX=/usr
INCLUDES=-I$(PYPREFIX)/include/python$(PYVERSION) -I./
LINK=-lpython$(PYVERSION)


all : network_server

network_server: main.o forward.so database.so message.so parser.so
	$(CC) -o $@ $^ $(INCLUDES) $(LINK)

main.o: main.c
	$(CC) -c $^ $(INCLUDES) $(LINK) 

forward.so: forward.c
	$(CC) $(INCLUDES) $(LINK) -shared -o forward.so -fPIC forward.c

database.so: database.c
	$(CC) $(INCLUDES) $(LINK) -shared -o database.so -fPIC database.c

message.so: message.c
	$(CC) $(INCLUDES) $(LINK) -shared -o message.so -fPIC message.c

parser.so: parser.c
	$(CC) $(INCLUDES) $(LINK) -shared -o parser.so -fPIC parser.c

forward.c: forward.pyx
	cython forward.pyx

database.c: database.pyx
	cython database.pyx 

main.c: main.pyx
	cython --embed main.pyx 

message.c: message.pyx
	cython message.pyx 

parser.c: parser.pyx
	cython parser.pyx 

clean: 
	rm *.c *.o *.so *.pyc network_server 2> /dev/null 
