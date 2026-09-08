from kivy.uix.boxlayout import BoxLayout
from kivy.uix.button import Button
from kivy.properties import *

class MyButton(Button):
    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        self.text = "Hello World"
        self.size_hint = (0.5, 0.5)

class CustomWidget(BoxLayout):
    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        self.orientation = "vertical"
        self.spacing = 10.0