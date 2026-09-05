from kivy.uix.boxlayout import BoxLayout
from kivy.uix.button import Button
from kivy.uix.label import Label
from kivy.uix.textinput import TextInput
from kivy.app import App


class ComplexWidget(BoxLayout):

    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        self._bindings = []
        app = App.get_running_app()
        self.orientation = "vertical"
        label_E601E7C3 = Label(font_size=24.0)
        label_E601E7C3.text = app.title
        app.bind(title=label_E601E7C3.setter("text"))
        self.add_widget(label_E601E7C3)
        box_5736D8A4 = BoxLayout()
        button_66B05D98 = Button(text="Save")
        _callback_0 = lambda instance: self.save_data()
        button_66B05D98.bind(on_press=_callback_0)
        box_5736D8A4.add_widget(button_66B05D98)
        button_54910EAA = Button(text="Load")
        _callback_1 = lambda instance: self.load_data()
        button_54910EAA.bind(on_press=_callback_1)
        box_5736D8A4.add_widget(button_54910EAA)
        button_573825D5 = Button(text="Clear")
        _callback_2 = lambda instance: self.clear_all()
        button_573825D5.bind(on_release=_callback_2)
        box_5736D8A4.add_widget(button_573825D5)
        self.add_widget(box_5736D8A4)
        my_input = TextInput()
        my_input.text = app.current_text
        app.bind(current_text=my_input.setter("text"))
        self.ids.my_input = my_input
        _callback_3 = lambda instance: self.on_text_changed()
        my_input.bind(on_text=_callback_3)
        self.add_widget(my_input)
        self._bindings.append((button_66B05D98, "on_press", _callback_0))
        self._bindings.append((button_54910EAA, "on_press", _callback_1))
        self._bindings.append((button_573825D5, "on_release", _callback_2))
        self._bindings.append((my_input, "on_text", _callback_3))

    def __del__(self):
        for (obj, prop, callback) in self._bindings:
            try:
                obj.unbind(**{prop: callback})
            except:
                pass