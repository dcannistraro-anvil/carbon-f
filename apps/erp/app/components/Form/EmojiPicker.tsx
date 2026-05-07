import { useControlField, useField } from "@carbon/form";
import {
  Button,
  FormControl,
  FormErrorMessage,
  Popover,
  PopoverContent,
  PopoverFooter,
  PopoverTrigger,
  useMode
} from "@carbon/react";
import data from "@emoji-mart/data";
import Picker from "@emoji-mart/react";
import { useState } from "react";
import { LuSmilePlus, LuTrash } from "react-icons/lu";

type EmojiPickerProps = {
  name: string;
  label?: string;
};

type EmojiData = {
  native: string;
  id: string;
  name: string;
};

const EmojiPicker = ({ name }: EmojiPickerProps) => {
  const { error } = useField(name);
  const [value, setValue] = useControlField<string>(name);
  const [open, setOpen] = useState(false);
  const mode = useMode();
  const pickerTheme = mode;

  const onEmojiSelect = (emoji: EmojiData) => {
    setValue(emoji.native);
    setOpen(false);
  };

  const onRemove = () => {
    setValue("");
    setOpen(false);
  };

  return (
    <FormControl>
      <input type="hidden" name={name} value={value ?? ""} />
      <Popover open={open} onOpenChange={setOpen}>
        <PopoverTrigger asChild>
          {value ? (
            <button
              type="button"
              className="inline-flex items-center justify-center rounded-md h-16 w-16 text-5xl hover:bg-accent transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2"
            >
              {value}
            </button>
          ) : (
            <div>
              <Button type="button" variant="ghost" leftIcon={<LuSmilePlus />}>
                Add icon
              </Button>
            </div>
          )}
        </PopoverTrigger>
        <PopoverContent
          className="w-auto p-0 border-0"
          align="start"
          sideOffset={8}
        >
          <Picker
            data={data}
            onEmojiSelect={onEmojiSelect}
            theme={pickerTheme}
            previewPosition="none"
            skinTonePosition="none"
            navPosition="bottom"
            perLine={8}
          />
          {value && (
            <PopoverFooter className="flex justify-center">
              <Button
                variant="destructive"
                onClick={onRemove}
                leftIcon={<LuTrash className="h-4 w-4 mr-2" />}
              >
                Remove icon
              </Button>
            </PopoverFooter>
          )}
        </PopoverContent>
      </Popover>
      {error && <FormErrorMessage>{error}</FormErrorMessage>}
    </FormControl>
  );
};

export default EmojiPicker;
