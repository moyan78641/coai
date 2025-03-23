import { Button } from "./ui/button.tsx";
import { useConversationActions, useMessages } from "@/store/chat.ts";
import { MessageSquarePlus, Home } from "lucide-react";
import { openWindow } from "@/utils/device.ts";

function ProjectLink() {
  const messages = useMessages();

  const { toggle } = useConversationActions();

  return messages.length > 0 ? (
    <Button
      variant="outline"
      size="icon"
      onClick={async () => await toggle(-1)}
    >
      <MessageSquarePlus className={`h-4 w-4`} />
    </Button>
  ) : (
    <Button
      variant="outline"
      size="icon"
      onClick={() => openWindow("/")}
    >
      <Home className="h-[1.2rem] w-[1.2rem] rotate-0 scale-100" />
    </Button>
  );
}

export default ProjectLink;
