from kivy.uix.boxlayout import BoxLayout
from kivy.uix.button import Button
from kivy.uix.label import Label
from kivy.app import App


class MyWidget(BoxLayout):

    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        self._bindings = []
        app = App.get_running_app()
        label_7145D272 = Label(font_size=20.0)
        label_7145D272.text = app.some_prop
        app.bind(some_prop=label_7145D272.setter("text"))
        self.add_widget(label_7145D272)
        button_32B27BC4 = Button(text="Click Me")
        _callback_0 = button_32B27BC4.bind(on_press=lambda instance: app.handle_click())
        self.add_widget(button_32B27BC4)
        self._bindings.append((button_32B27BC4, "on_press", _callback_0))

    def __del__(self):
        for (obj, prop, callback) in self._bindings:
            try:
                obj.unbind(**{prop: callback})
            except:
                pass