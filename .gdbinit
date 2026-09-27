set pagination off
set confirm off
 
file kernel.bin
 
set architecture i386:x86-64
 
target remote :1234
 
break _start
break _start64
break kernel_main
 
commands 2
    echo \n*** long mode entered -- architecture switched to i386:x86-64 ***\n
end
