export function Modal({ children, isOpen, onClose }: { 
  children: React.ReactNode; 
  isOpen: boolean; 
  onClose: () => void;
}) {
  if (!isOpen) return null
  
  return (
    <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50">
      <div className="bg-white rounded-lg p-6 max-w-md w-full">
        {children}
      </div>
    </div>
  )
}
