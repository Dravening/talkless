I was working on a section on the gooey innards of journaling for *The Definitive Guide*, but then I realized it’s an implementation detail that most people won’t care about. However, I had all of these nice diagrams just laying around.

![image](.\img\1.jpg)

 Good idea, Patrick! So, how does journaling work? Your disk has your data files and your journal files, which we’ll represent like this:

![image](.\img\2.png)

 When you start up *mongod*, it maps your data files to a *shared view*. Basically, the operating system says: “Okay, your data file is 2,000 bytes on disk. I’ll map that to memory address 1,000,000-1,002,000. So, if you read the memory at memory address 1,000,042, you’ll be getting the 42nd byte of the file.“ (Also, the data won’t necessary be loaded until you actually access that memory.)

![image](.\img\3.png)

This memory is still backed by the file: if you make changes in memory, the operating system will flush these changes to the underlying file. This is basically how *mongod* works without journaling: it asks the operating system to flush in-memory changes every 60 seconds. However, with journaling, *mongod* makes a second mapping, this one to a *private view*. Incidentally, this is why enabling journalling doubles the amount of virtual memory *mongod* uses.

![image](.\img\4.png)

Note that the private view is not connected to the data file, so the operating system cannot flush any changes from the private view to disk. Now, when you do a write, *mongod* writes this to the private view.

![image](.\img\5.png) 

*mongod* will then write this change to the journal file, creating a little description of which bytes in which file changed.

![image](.\img\6.png)

The journal appends each change description it gets.

![image](.\img\7.png)

At this point, the write is safe. If *mongod* crashes, the journal can replay the change, even though it hasn’t made it to the data file yet. The journal will then replay this change on the shared view.

![image](.\img\8.png)

Finally, at a glacial speed compared to everything else, the shared view will be flushed to disk. By default, mongod requests that the OS do this every 60 seconds.

![image](.\img\9.png)

The last step is that *mongod* remaps the shared view to the private view. This prevents the private view from getting too “dirty” (having too many changes from the shared view it was mapped from).

![image](.\img\10.png)

And that’s how journaling works. Thanks to Richard, who gave the best explanation of this I’ve heard (Richard is going to be teaching [an online course on MongoDB](http://education.10gen.com/courses/10gen/M101/2012_Fall/about) this fall, if you’re interested in more wisdom from the source).