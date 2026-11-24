using System;
using System.Runtime.InteropServices;
using System.Text;

namespace Remnexa.DefaultApplications
{
    // Read-only Shell API. Never execute registry command strings or write UserChoice.
    public static class AssociationReader
    {
        [DllImport("shlwapi.dll", CharSet = CharSet.Unicode, ExactSpelling = true)]
        private static extern int AssocQueryStringW(uint flags, uint kind,
            string association, string extra, StringBuilder output, ref uint length);

        public static string Query(string association, bool protocol, uint kind)
        {
            uint length = 0;
            uint flags = protocol ? 0x00001000u : 0u; // ASSOCF_IS_PROTOCOL
            AssocQueryStringW(flags, kind, association, null, null, ref length);
            if (length == 0 || length > 32768) return null;
            var output = new StringBuilder((int)length);
            return AssocQueryStringW(flags, kind, association, null, output, ref length) == 0
                ? output.ToString() : null;
        }
    }
}
