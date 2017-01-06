#! /usr/bin/python

import sys
import os
import time

import os 
import time 
import ntplib 
c = ntplib.NTPClient() 
response = c.request('pool.ntp.org') 
ts = response.tx_time 
_date = time.strftime('%Y-%m-%d',time.localtime(ts)) 
_time = time.strftime('%X',time.localtime(ts)) 
this_time = os.system('date {} && time {}'.format(_date,_time))

TIMEFMT = "%Y-%m-%d %H:%M:%S"

#
## Line 1 XiErQi Station(Line 13) - Incubator - ISB - Oracle Building
##
## Morning Runs	7:40am - 9:30am
##     Capacity
##       4 buses, 50 seats for each
##     Route
##       XiErQi Station(Line 13) -> Incubator -> ISB -> Oracle Building
##     Departure Time
##       7:40am/7:50am/8:00am/8:10am/8:20am/8:30am
##       8:40am/8:50am/9:00am/9:10am/9:20am/9:30am
##       1 bus at each departure time
##
## Evening Runs 	17:40pm - 20:00pm
##     Route
##       Oracle Building -> ISB -> Incubator -> XiErQi Station(Line 13)
##     Departure Time
##       17:40pm/18:10pm/18:40pm (3 buses at each departure time)
##       19:00pm/19:30pm/20:00pm (1 bus at each departure time)
#
S  = ' ' * 4
XO = "XiErQi Station(Line 13) -> Incubator -> ISB -> Oracle Building"
OX = "Oracle Building -> ISB -> Incubator -> XiErQi Station(Line 13)"
MR = "%sMorning Runs: 07:40am - 09:30am <10m>" % S
ER = "%sEvening Runs: 17:10pm - 20:00pm <30m>" % S
A  = "Route: %s\n%sCapacity: %d bus with 50 seats for each" % (XO, S, 1)
B  = "Route: %s\n%sCapacity: %d buses with 50 seats for each" % (OX, S, 3)
C  = "Route: %s\n%sCapacity: %d bus with 50 seats for each" % (OX, S, 1)
TT = ["07:40,A", "07:50,A", "08:00,A", "08:10,A",
      "08:20,A", "08:30,A", "08:40,A", "08:50,A",
      "09:00,A", "09:10,A", "09:20,A", "09:30,A",
      "17:10,B", "17:40,B", "18:10,B", "18:40,B",
      "19:00,C", "19:30,C", "20:00,C"]

#
# Public functions to print out colorful string on terminal
#
def isatty():
	s = os.getenv("ISATTY")
	if s == None:
		s = ""

	if s.upper() == "YES":
		return (True)

	if s.upper() == "NO":
		return (False)

	if sys.stdout.isatty() and sys.stderr.isatty():
		return (True)
	return (False)

def str2gray(s):
	if isatty():
		return ("\033[1;30m%s\033[m" % s)
	return (s)

def str2red(s):
	if isatty():
		return ("\033[1;31m%s\033[m" % s)
	return (s)

def str2green(s):
	if isatty():
		return ("\033[1;32m%s\033[m" % s)
	return (s)

def str2yellow(s):
	if isatty():
		return ("\033[1;33m%s\033[m" % s)
	return (s)

def str2blue(s):
	if isatty():
		return ("\033[1;34m%s\033[m" % s)
	return (s)

def str2magenta(s):
	if isatty():
		return ("\033[1;35m%s\033[m" % s)
	return (s)

def str2cyan(s):
	if isatty():
		return ("\033[1;36m%s\033[m" % s)
	return (s)

def str2white(s):
	if isatty():
		return ("\033[1;37m%s\033[m" % s)
	return (s)

def getseconds(dayfrom, dayto):
	tfa = time.strptime(dayfrom, TIMEFMT)
	tfs = time.mktime(tfa)
	tta = time.strptime(dayto, TIMEFMT)
	tts = time.mktime(tta)
	nsecs = tts - tfs
	return (nsecs)

def get_minsecs(l):
	#this_time = time.strftime(TIMEFMT, time.localtime())
	prefix = this_time.split(' ')[0]

	that_time = ""
	that_type = ""
	target = 24 * 60 * 60
	for i in l:
		i_list = i.split(',')
		i_time = i_list[0]
		i_type = i_list[1]
		t = "%s %s:00" % (prefix, i_time)
		n = getseconds(this_time, t)
		#print "this: %s, that: %s, nsecs=%d" % (this_time, t , n)
		if n <= 0:
			continue

		if n < target:
			target = n
			that_time = i_time
			that_type = i_type
			#print "X: %d %s" % (n, i)
	if that_type == 'A':
		msg = A
	elif that_type == "B":
		msg = B
	elif that_type == "C":
		msg = C
	else:
		msg = ""

	d    = int(target / (24 * 3600))
	left = target - d * 24 * 3600
	h    = int(left / 3600)
	left = left - h * 3600
	m    = int(left / 60)
	left = left - m * 60
	s    = int(left)

	if len(that_time) > 0:
		s1 = str2red("Next bus time:")
		s2 = str2yellow(that_time)
		s3 = str2red("Time left:")
		s4 = str2yellow("%02d:%02d:%02d" % (h, m, s))
		print "*" * 80
		print "\n%s%s %s | %s %s" % (' ' * 10, s1, s2, s3, s4)
		print "%sCurrent time: %s\n" % (' ' * 19, this_time)
		print "*" * 80
		print "%s%s\n\n%s\n%s" % (S, msg, MR, ER)
		print "*" * 80
		print str2red("Xtimeleft=%d" % (int(target/60)))
	else:
		print "\n***** No bus for you now *****\n"

	return (0)

def main():
	get_minsecs(TT)
	return (0)

if __name__ == "__main__":
	sys.exit(main())
