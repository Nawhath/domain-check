# domain-check
ตัวอย่างสร้าาง Crontab 
0 1 * * * /opt/domain-check/domain-check.sh -a  -e user@domain.com -x 90 -f /opt/domain-check/domain-list.txt > /opt/domain-check/domaincheck.txt
