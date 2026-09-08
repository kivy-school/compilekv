from kivy.uix.boxlayout import BoxLayout
from kivy.uix.label import Label
from kivy.app import App
from kivy.properties import ObjectProperty

class MyWidget(BoxLayout):
    text_value = ObjectProperty(None)
    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        app = App.get_running_app()
        self.text_value = app.some_prop
        app.bind(some_prop=self.setter("text_value"))

class AnotherWidget(Label):
    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        app = App.get_running_app()
        self.text = app.title
        self.font_size = 20.0
        app.bind(title=self.setter("text"))
        app.bind(title=lambda instance, app_description: widget.text = str(app_description))
        