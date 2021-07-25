<pre>
<?php

print("Hello World\n\n");
print("Time: ");
print `date`;
print("\n");
print("Details of server:\n");
print `ifconfig`;
print("\n");
print("RAM:\n");
print `free -m`;
print("\n");
print("Volumes:\n");
print `df -h`;
print("\n");
print("CPU:\n");
print `lscpu`;

?>
</pre>
