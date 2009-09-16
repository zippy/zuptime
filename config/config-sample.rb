# if your machine doesn't have /usr/bin/curl then you need to specify the path (and options)
# to the command zuptime will use to check the websites.

#CMD = '/usr/local/bin/curl'
CMD = '/usr/bin/wget --no-check-certificate -O -'
