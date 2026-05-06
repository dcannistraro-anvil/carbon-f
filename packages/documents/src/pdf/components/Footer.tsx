import { Text, View } from "@react-pdf/renderer";
import { createTw } from "react-pdf-tailwind";

const tw = createTw({
  theme: {
    fontFamily: {
      sans: ["Helvetica", "Arial", "sans-serif"]
    }
  }
});

interface FooterProps {
  label?: string;
  documentId?: string | null;
}

const Footer = ({ label, documentId }: FooterProps) => {
  return (
    <View style={tw("absolute bottom-0 left-0 right-0 px-10 pb-5")} fixed>
      <View style={tw("border-t border-gray-200 pt-2")}>
        <View
          style={tw(
            "flex flex-row justify-between items-center text-xs text-gray-500"
          )}
        >
          <Text>{label ?? ""}</Text>
          <Text
            render={({ pageNumber, totalPages }) =>
              `${documentId ? `${documentId}   ` : ""}Page ${pageNumber} of ${totalPages}`
            }
          />
        </View>
      </View>
    </View>
  );
};

export default Footer;
