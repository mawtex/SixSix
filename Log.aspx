<%@ Page Language="C#" AutoEventWireup="true" CodeBehind="Log.aspx.cs"  %>

<!DOCTYPE html>

<html xmlns="http://www.w3.org/1999/xhtml">
<head runat="server">
    <title>aspx log test</title>
</head>
<body>
    <form id="form1" runat="server">
        <div>
            logged...
            <%
            System.Diagnostics.Trace.TraceWarning("web forms logging here!!");
                
            %>
        </div>
    </form>
</body>
</html>
