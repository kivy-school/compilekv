

i dont like how @compilekv/KvToPyClass/Sources/KvToPyClass/KvToPyClassGenerator.swift was envolving with this struct and endless of functions ... 

we need much better seperation and more usage of classes where keeping refs matters... 

in compilekv/KvToPyClass/Sources/KvToPyClass/Content
i made some seperation already, and added some new ways to express some of it
but not implemented anywhere since it mostly just illustrate how to handle example
kivy property types

like in PySwiftKit which is my own design 
stuff like generating init function is its own generator class
functions its own class
properties own class

and general more generic thinking would allow more flexable generation
once we allow to allow SwiftyKvLang and this is express other Widget names like SwiftUI names and stuff like that.. 

instead endless of switch case solutions only normal enums then atleast use some enums for Protocol based stuff, like was showed in kivy properties...

