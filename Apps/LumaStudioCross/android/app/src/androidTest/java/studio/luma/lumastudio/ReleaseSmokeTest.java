package studio.luma.lumastudio;

import android.content.Context;
import android.content.Intent;
import android.content.pm.ApplicationInfo;
import android.graphics.BitmapFactory;
import android.os.SystemClock;
import androidx.test.ext.junit.runners.AndroidJUnit4;
import androidx.test.platform.app.InstrumentationRegistry;
import androidx.test.uiautomator.By;
import androidx.test.uiautomator.Configurator;
import androidx.test.uiautomator.UiDevice;
import androidx.test.uiautomator.UiObject2;
import androidx.test.uiautomator.StaleObjectException;
import java.io.File;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.security.MessageDigest;
import java.util.Arrays;
import java.util.Comparator;
import java.util.regex.Pattern;
import org.json.JSONObject;
import org.junit.Test;
import org.junit.runner.RunWith;
import static org.junit.Assert.*;

/** Runs against the independently signed, non-debuggable distribution APK. */
@RunWith(AndroidJUnit4.class)
public class ReleaseSmokeTest {
    private final Context context = InstrumentationRegistry.getInstrumentation().getTargetContext();
    private final UiDevice device = UiDevice.getInstance(InstrumentationRegistry.getInstrumentation());
    private final File library = new File(context.getFilesDir(), "LumaStudioPortable");

    private UiObject2 named(String text) {
        UiObject2 node = device.findObject(By.text(text));
        if(node==null)node=device.findObject(By.desc(text));
        if(node==null&&text.endsWith(".jpg"))node=device.findObject(By.descStartsWith(text+","));
        return node;
    }
    private void tap(String text) throws Exception {
        for(int i=0;i<6;i++) {
            try {waitNamed(text).click();return;}
            catch(StaleObjectException stale) {SystemClock.sleep(150);}
        }
        throw new AssertionError("Control repeatedly changed during transition: "+text);
    }
    private UiObject2 waitNamed(String text) throws Exception {
        for (int i=0;i<100;i++) {
            UiObject2 node=named(text);
            if(node!=null) return node;
            SystemClock.sleep(100);
        }
        throw new AssertionError("Missing control: "+text);
    }
    private JSONObject firstPhoto() throws Exception {
        return new JSONObject(new String(Files.readAllBytes(new File(library,"library.json").toPath()),StandardCharsets.UTF_8))
            .getJSONArray("photos").getJSONObject(0);
    }
    private double exposure() throws Exception {
        return firstPhoto().getJSONObject("recipe").getJSONObject("values").getDouble("exposure");
    }
    private void waitPreview() throws Exception {
        for(int i=0;i<200;i++) {
            if(device.findObject(By.descContains(" × "))!=null)return;
            SystemClock.sleep(100);
        }
        throw new AssertionError("Decoded preview must be visible");
    }
    private double brightness(android.graphics.Bitmap image) {
        double total=0;int count=0;
        for(int y=0;y<image.getHeight();y+=Math.max(1,image.getHeight()/40))
            for(int x=0;x<image.getWidth();x+=Math.max(1,image.getWidth()/40)) {
                int c=image.getPixel(x,y);
                total+=.2126*android.graphics.Color.red(c)+.7152*android.graphics.Color.green(c)+.0722*android.graphics.Color.blue(c);
                count++;
            }
        return total/count;
    }
    private void launch() {
        Intent intent=context.getPackageManager().getLaunchIntentForPackage(context.getPackageName());
        assertNotNull(intent);
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK|Intent.FLAG_ACTIVITY_CLEAR_TASK);
        context.startActivity(intent);
    }
    @Test public void signedReleaseImportsEditsExportsAndRestarts() throws Exception {
        Configurator.getInstance().setWaitForIdleTimeout(300);
        assertEquals("Release APK must not be debuggable",0,context.getApplicationInfo().flags&ApplicationInfo.FLAG_DEBUGGABLE);
        File evidence=context.getExternalFilesDir("release-qa");
        assertNotNull("External evidence directory",evidence); evidence.mkdirs();
        try {
            launch();
            waitNamed("导入照片");
            if(!new File(library,"library.json").exists()) waitNamed("用示例照片体验").click();
            for(int i=0;i<100&&!new File(library,"library.json").exists();i++)SystemClock.sleep(100);
            JSONObject photo=firstPhoto();
            File original=new File(photo.getString("path"));
            if(!original.isAbsolute()) original=new File(library,photo.getString("path"));
            byte[] before=MessageDigest.getInstance("SHA-256").digest(Files.readAllBytes(original.toPath()));
            waitNamed("重置全部参数").click();
            for(int i=0;i<100&&Math.abs(exposure())>0.01;i++)SystemClock.sleep(100);
            UiObject2 slider=null, exposureRow=null;
            for(int i=0;i<100;i++) {
                exposureRow=device.findObject(By.descStartsWith("曝光\n"));
                if(exposureRow!=null) slider=exposureRow.findObject(By.desc(Pattern.compile("[0-9]+%")));
                if(slider!=null)break;
                SystemClock.sleep(100);
            }
            assertNotNull("Exposure slider must be accessible",slider);
            android.graphics.Rect bounds=slider.getVisibleBounds(), row=exposureRow.getVisibleBounds();
            double old=exposure();
            device.swipe(bounds.centerX(),bounds.centerY(),bounds.centerX()+row.width()/8,bounds.centerY(),40);
            for(int i=0;i<100&&Math.abs(exposure()-old)<0.01;i++)SystemClock.sleep(100);
            assertTrue("Dragging changes the persisted recipe",Math.abs(exposure()-old)>0.01);
            tap("肤色");tap("高强度");
            for(int i=0;i<100&&firstPhoto().getJSONObject("recipe").getJSONObject("values").optDouble("skinWhiten",0)<.5;i++)SystemClock.sleep(100);
            assertEquals(1,firstPhoto().getJSONObject("recipe").getJSONObject("values").getDouble("skinSmooth"),0.001);
            assertEquals(0,firstPhoto().getJSONObject("recipe").getJSONObject("values").getDouble("skinTexture"),0.001);
            SystemClock.sleep(1200);
            assertTrue(device.takeScreenshot(new File(evidence,"android-release-editor.png")));
            waitNamed("导出").click();
            UiObject2 save=null;
            for(int i=0;i<200;i++) {
                save=device.findObject(By.res("android:id/button1"));
                if(save!=null&&save.isEnabled())break;
                SystemClock.sleep(100);
            }
            assertNotNull("System save picker must open",save);
            save.click();
            waitNamed("照片已交给系统保存");
            waitNamed("导出");
            File[] exports=new File(library,"Exports").listFiles(f->f.getName().endsWith(".jpg"));
            assertNotNull(exports);assertTrue(exports.length>0);
            Arrays.sort(exports,Comparator.comparingLong(File::lastModified));
            android.graphics.Bitmap bitmap=BitmapFactory.decodeFile(exports[exports.length-1].getPath());
            assertNotNull("Export is a valid JPEG",bitmap);
            android.graphics.Bitmap source=BitmapFactory.decodeFile(original.getPath());
            assertNotNull(source);
            assertEquals(source.getWidth(),bitmap.getWidth());assertEquals(source.getHeight(),bitmap.getHeight());
            assertTrue("Positive exposure changes actual exported pixels",brightness(bitmap)>brightness(source)+8);
            source.recycle();bitmap.recycle();
            assertArrayEquals("Source stays unchanged",before,MessageDigest.getInstance("SHA-256").digest(Files.readAllBytes(original.toPath())));
            double saved=exposure();
            launch();waitNamed("导出");waitPreview();
            assertEquals("Restart preserves edits",saved,exposure(),0.0001);
            assertTrue(device.takeScreenshot(new File(evidence,"android-release-restarted.png")));
            int count=new JSONObject(new String(Files.readAllBytes(new File(library,"library.json").toPath()),StandardCharsets.UTF_8)).getJSONArray("photos").length();
            waitNamed("导入照片").click();
            for(int i=0;i<30&&named("LumaStudio-QA-import.jpg")==null;i++)SystemClock.sleep(100);
            if(named("LumaStudio-QA-import.jpg")==null) {
                UiObject2 roots=named("Show roots");
                if(roots!=null)tap("Show roots");
                tap("Downloads");
            }
            tap("LumaStudio-QA-import.jpg");
            waitNamed("导出");
            int imported=count;
            for(int i=0;i<100&&imported==count;i++) {
                imported=new JSONObject(new String(Files.readAllBytes(new File(library,"library.json").toPath()),StandardCharsets.UTF_8)).getJSONArray("photos").length();
                if(imported==count)SystemClock.sleep(100);
            }
            assertEquals("System picker imports an external JPEG",count+1,imported);
        } finally {
            device.dumpWindowHierarchy(new File(evidence,"android-release-ui.xml"));
        }
    }
}
