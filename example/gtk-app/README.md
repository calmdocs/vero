# Linux example

A GTK4 interface for the Go worker in `../worker`: a progress bar and a restart
button on each row, and a footer showing what the worker is doing.

On Linux:

```bash
sudo apt-get install -y python3-gi gir1.2-gtk-4.0
./build.sh
./main.py
```

From a Mac, without a Linux machine. This builds both pieces in a container,
runs the app on a virtual display, and opens it in Screen Sharing:

```bash
../../scripts/run-linux.sh
```
